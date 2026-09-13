import SwiftUI
import Observation
import CloudKit
import CoreData
import ServiceManagement
import WidgetKit
import DaydoCore
import OSLog

@MainActor @Observable
final class AppModel {
    private static let log = Logger(subsystem: DaydoConstants.bundleID, category: "Lifecycle")
    var snapshot = TaskSnapshot()
    var isLoading = true
    var hasStarted = false
    var errorMessage: String?
    var cloudStatus = "任务保存在本机"
    var activeSelection: StoreSelection?
    var pendingCloudSelection: StoreSelection?
    var notificationPermission = false
    var launchAtLogin = false
    var navigationRequest: AppNavigationRequest?
    var requestNewTask = false
    var isPreview = false
    var lastRefresh = Date()
    var repository: TaskRepository?
    var isReady: Bool { repository != nil }
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var isSwitchingStore = false
    @ObservationIgnored private var isCheckingCloud = false
    @ObservationIgnored private var recheckCloud = false
    @ObservationIgnored let notifications = NotificationService()
    private var pendingUndo: (@MainActor () async -> Void)?

    var remindersEnabled = UserDefaults.standard.object(forKey: "remindersEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(remindersEnabled, forKey: "remindersEnabled") }
    }
    var canUndo: Bool { pendingUndo != nil }

    func start() async {
        Self.log.notice("Application startup without app sign-in")
        #if DEBUG
        if CommandLine.arguments.contains("--ui-preview") {
            await startPreview()
            return
        }
        #endif
        installObservers()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        notificationPermission = await notifications.status() == .authorized
        await retryOpen()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    func retryOpen() async {
        isLoading = true
        do {
            let initial = await StoreSelection.forStartup(previous: try SharedEnvironment.selection(),
                                                           accessLocked: try SharedEnvironment.isAccessLocked(),
                                                           local: CloudAccountService.localSelection()) { previous, allowCached in
                await CloudAccountService.resolve(previous: previous, allowCached: allowCached).selection
            }
            cloudStatus = initial.cloudEnabled ? "正在检查 iCloud" : "任务保存在本机"
            await activate(initial)
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
        // The local store is usable before a network account lookup finishes.
        await checkCloudAccount()
    }

    private func activate(_ selection: StoreSelection) async {
        isSwitchingStore = true
        do {
            try SharedEnvironment.setAccessLocked(true)
            await notifications.cancelAll()
            if let repository { try repository.close() }
            repository = nil
            snapshot = TaskSnapshot()
            pendingUndo = nil
            try SharedEnvironment.select(selection)
            let repo = try TaskRepository(storeURL: SharedEnvironment.storeURL(selection),
                                          authorization: StoreAccessGate(namespace: selection.namespace),
                                          cloudContainerID: selection.cloudEnabled ? DaydoConstants.cloudContainerID : nil)
            repository = repo
            activeSelection = selection
            try SharedEnvironment.setAccessLocked(false)
            isSwitchingStore = false
            await refresh()
            WidgetCenter.shared.reloadAllTimelines()
            Self.log.notice("Data space is ready")
        } catch {
            Self.log.error("Store activation failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)")
            errorMessage = error.localizedDescription
            repository = nil
            isSwitchingStore = false
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func refresh() async {
        guard !isRefreshing, !isSwitchingStore, let repository else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let current = try await Task.detached(priority: .userInitiated) {
                try repository.consumeHistory(consumer: "main")
                return try repository.snapshot()
            }.value
            guard self.repository === repository, !isSwitchingStore else { return }
            let changed = current != snapshot
            snapshot = current
            lastRefresh = Date()
            if !isPreview {
                if changed { WidgetCenter.shared.reloadTimelines(ofKind: DaydoConstants.widgetKind) }
                if let activeSelection {
                    try await notifications.reconcile(current, namespace: activeSelection.namespace, enabled: remindersEnabled)
                    try SharedEnvironment.publishStatus(CoordinatorStatus(namespace: activeSelection.namespace,
                                                                          syncMessage: cloudStatus,
                                                                          notificationAuthorized: notificationPermission))
                }
            }
        } catch {
            guard self.repository === repository, !isSwitchingStore else { return }
            Self.log.error("Refresh failed: \((error as? DaydoError)?.code ?? (error as NSError).domain, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func checkCloudAccount(explicitChange: Bool = false) async {
        guard !isPreview else { return }
        if isCheckingCloud {
            if explicitChange {
                recheckCloud = true
                isSwitchingStore = true
                try? SharedEnvironment.setAccessLocked(true)
                await notifications.cancelAll()
                snapshot = TaskSnapshot()
                WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }
        isCheckingCloud = true
        defer { isCheckingCloud = false }
        var requireFresh = explicitChange
        let hasLocalData = !snapshot.tasks.isEmpty || !snapshot.lists.isEmpty
        repeat {
            recheckCloud = false
            if requireFresh {
                isSwitchingStore = true
                try? SharedEnvironment.setAccessLocked(true)
                await notifications.cancelAll()
                snapshot = TaskSnapshot()
                WidgetCenter.shared.reloadAllTimelines()
            }
            let result = await CloudAccountService.resolve(previous: activeSelection, allowCached: !requireFresh)
            if recheckCloud { requireFresh = true; continue }
            if result.selection != activeSelection {
                if activeSelection?.cloudEnabled == false, result.selection.cloudEnabled,
                   hasLocalData {
                    pendingCloudSelection = result.selection
                    cloudStatus = "iCloud 已就绪，等待合并本机任务"
                    try? SharedEnvironment.setAccessLocked(false)
                    isSwitchingStore = false
                    await refresh()
                } else {
                    pendingCloudSelection = nil
                    cloudStatus = result.status
                    await activate(result.selection)
                }
            } else {
                // Do not replace a specific CloudKit error with a generic connected label.
                if !cloudStatus.contains("重试") && cloudStatus != "iCloud 已同步" { cloudStatus = result.status }
                try? SharedEnvironment.setAccessLocked(false)
                isSwitchingStore = false
                await refresh()
            }
            requireFresh = true
        } while recheckCloud
    }

    func migrateLocalToCloud() async {
        guard let target = pendingCloudSelection, let repository else { return }
        do {
            let backup = try repository.exportBackup()
            await activate(target)
            guard activeSelection == target, let destination = self.repository else { return }
            try destination.importBackup(backup)
            pendingCloudSelection = nil
            cloudStatus = "iCloud 已连接"
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func run<T: Sendable>(_ operation: @escaping @Sendable (TaskRepository) throws -> T) async -> T? {
        guard let repository, !isSwitchingStore else { errorMessage = "任务存储尚未就绪，请稍后重试。"; return nil }
        do {
            let result = try await Task.detached(priority: .userInitiated) { try operation(repository) }.value
            await refresh()
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func complete(_ occurrence: TaskOccurrence) async {
        let completed = !occurrence.isCompleted
        if await run({ try $0.setCompletion(id: occurrence.taskID, completed: completed, originalDay: occurrence.originalDay) }) != nil {
            pendingUndo = { [weak self] in
                _ = await self?.run { try $0.setCompletion(id: occurrence.taskID, completed: !completed, originalDay: occurrence.originalDay) }
            }
        }
    }
    func delete(_ occurrence: TaskOccurrence) async {
        if await run({ try $0.setDeleted(id: occurrence.taskID, deleted: true, originalDay: occurrence.originalDay) }) != nil {
            pendingUndo = { [weak self] in
                _ = await self?.run { try $0.setDeleted(id: occurrence.taskID, deleted: false, originalDay: occurrence.originalDay) }
            }
        }
    }
    func undo() async { let action = pendingUndo; pendingUndo = nil; await action?() }
    func move(_ occurrence: TaskOccurrence, to day: LocalDay, minute: Int? = nil, duration: Int? = nil) async {
        var fields = occurrence.fields
        fields.day = day
        if let minute { fields.startMinute = minute }
        if let duration { fields.durationMinutes = duration }
        let updated = fields
        _ = await run { try $0.updateTask(id: occurrence.taskID, fields: updated, expectedRevision: occurrence.revision,
                                          originalDay: occurrence.originalDay, scope: occurrence.originalDay == nil ? .task : .occurrence) }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { errorMessage = error.localizedDescription }
    }
    func setReminderEnabled(_ enabled: Bool) async {
        do {
            if enabled { notificationPermission = try await notifications.requestPermission() }
            remindersEnabled = enabled && notificationPermission
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    func openURL(_ url: URL) {
        guard let request = AppNavigationRequest(url: url) else { return }
        navigationRequest = request
        let windows = NSApp.windows.filter {
            $0.identifier?.rawValue == "main" || $0.identifier?.rawValue.hasPrefix("main-") == true
        }
        Self.log.notice("Navigation delivered; main windows: \(windows.count, privacy: .public), visible: \(windows.filter(\.isVisible).count, privacy: .public)")
    }
    private func installObservers() {
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.xiaolin.daydo.account-check"),
                                                                              object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.checkCloudAccount(explicitChange: true)
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                                                 object: nil, queue: .main) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let status: String
            if let error = event.error {
                status = "iCloud 等待重试：\(error.localizedDescription)"
                #if DEBUG
                try? FileHandle.standardError.write(contentsOf: Data("[Daydo CloudKit] \(error as NSError)\n".utf8))
                #endif
            }
            else if event.endDate == nil { status = "iCloud 正在同步" }
            else { status = "iCloud 已同步" }
            Task { @MainActor in
                guard self?.activeSelection?.cloudEnabled == true else { return }
                self?.cloudStatus = status
                await self?.refresh()
            }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(DaydoConstants.changeNotification),
                                                                              object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.checkCloudAccount(explicitChange: true) }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.checkCloudAccount()
                await self?.refresh()
            }
        })
    }
}

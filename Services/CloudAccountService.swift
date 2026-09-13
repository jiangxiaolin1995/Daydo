import Foundation
import CloudKit
import DaydoCore

struct CloudAccountResult: Sendable {
    var selection: StoreSelection
    var status: String
}

enum CloudAccountService {
    static func resolve(previous: StoreSelection?, allowCached: Bool) async -> CloudAccountResult {
        do {
            let container = CKContainer(identifier: DaydoConstants.cloudContainerID)
            let status = try await container.accountStatus()
            if status == .available {
                let recordID = try await container.userRecordID()
                return CloudAccountResult(selection: StoreSelection(namespace: SharedEnvironment.namespace(for: recordID.recordName, cloud: true),
                                                                     cloudEnabled: true), status: "iCloud 已连接")
            }
            if status == .couldNotDetermine || status == .temporarilyUnavailable, allowCached, let previous {
                return CloudAccountResult(selection: previous, status: "暂时离线，任务已保存在本机")
            }
            let local = previous?.cloudEnabled == false ? previous! : localSelection()
            return CloudAccountResult(selection: local, status: status == .noAccount ? "未登录系统 iCloud，本机保存" : "iCloud 不可用，本机保存")
        } catch {
            if allowCached, let previous {
                return CloudAccountResult(selection: previous, status: "等待 iCloud 连接：\(error.localizedDescription)")
            }
            return CloudAccountResult(selection: localSelection(), status: "iCloud 暂不可用：\(error.localizedDescription)")
        }
    }
    static func localSelection() -> StoreSelection {
        StoreSelection(namespace: SharedEnvironment.namespace(for: "daydo-local", cloud: false), cloudEnabled: false)
    }
}

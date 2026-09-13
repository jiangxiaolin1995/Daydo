#if DEBUG
import CloudKit
import DaydoCore
import Foundation

enum CloudDiagnostics {
    static func run() async {
        var report: [String: Any] = ["container": DaydoConstants.cloudContainerID]
        do {
            guard let selection = try SharedEnvironment.selection() else { throw DaydoError.unavailable("请先打开 Daydo。") }
            try StoreAccessGate(namespace: selection.namespace).requireAuthorization()
            let container = CKContainer(identifier: DaydoConstants.cloudContainerID)
            report["accountStatus"] = try await container.accountStatus().rawValue
            let zones = try await container.privateCloudDatabase.allRecordZones()
            report["privateZoneCount"] = zones.count
            report["coreDataZoneExists"] = zones.contains { $0.zoneID.zoneName == "com.apple.coredata.cloudkit.zone" }
            report["success"] = true
        } catch {
            report["success"] = false
            report["error"] = describe(error)
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? FileHandle.standardOutput.write(contentsOf: data + Data("\n".utf8))
        }
    }
    static func describe(_ error: any Error, depth: Int = 0) -> [String: Any] {
        let ns = error as NSError
        var result: [String: Any] = ["domain": ns.domain, "code": ns.code, "message": ns.localizedDescription]
        guard depth < 5 else { return result }
        if let reason = ns.userInfo["CKErrorDescription"] as? String { result["reason"] = reason }
        if let partial = (error as? CKError)?.partialErrorsByItemID {
            result["partialErrors"] = partial.values.map { describe($0, depth: depth + 1) }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? any Error {
            result["underlyingError"] = describe(underlying, depth: depth + 1)
        }
        return result
    }
}
#endif

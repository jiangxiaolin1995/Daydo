import Foundation

public enum MCPCompatibility {
    /// SDK 0.12.1 decodes experimental capabilities as [String: String], while the
    /// protocol permits arbitrary objects. Daydo does not negotiate experimental
    /// client capabilities, so leave these unsupported extensions out of decoding.
    public static func normalizeInitialization(_ data: Data) -> Data {
        guard var message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              message["method"] as? String == "initialize",
              var params = message["params"] as? [String: Any],
              var capabilities = params["capabilities"] as? [String: Any],
              capabilities["experimental"] is [String: Any] else { return data }
        capabilities.removeValue(forKey: "experimental")
        params["capabilities"] = capabilities
        message["params"] = params
        return (try? JSONSerialization.data(withJSONObject: message)) ?? data
    }
}

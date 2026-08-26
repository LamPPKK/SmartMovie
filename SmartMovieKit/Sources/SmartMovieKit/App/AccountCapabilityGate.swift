import Foundation

struct AccountCapabilityGate {
    private var resolved = false
    private var enabled = false
    private var pendingCallback: URL?

    mutating func resolve(enabled: Bool) -> URL? {
        self.enabled = enabled
        resolved = true
        defer { pendingCallback = nil }
        return enabled ? pendingCallback : nil
    }

    mutating func submit(_ url: URL) -> URL? {
        guard resolved else {
            pendingCallback = url
            return nil
        }
        return enabled ? url : nil
    }
}

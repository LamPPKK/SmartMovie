import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
public final class AccountSessionController {
    public enum State: Sendable {
        case checking
        case signedOut
        case authorizing
        case signedIn(AccountProfile)
        case failed(String)
    }

    public private(set) var state: State = .checking
    public private(set) var pendingAttempt: AuthAttempt?
    private let account: any AccountRepository
    private var pollingTask: Task<Void, Never>?

    public init(account: any AccountRepository) {
        self.account = account
    }

    public func refresh() async {
        do {
            state = .signedIn(try await account.profile())
        } catch {
            state = .signedOut
        }
    }

    public func begin(returnURI: URL, mode: String) async -> URL? {
        pollingTask?.cancel()
        state = .authorizing
        do {
            let attempt = try await account.createAuthAttempt(returnURI: returnURI, mode: mode)
            pendingAttempt = attempt
            if mode == "tv" { pollTV(attempt) }
            return attempt.authorizationUrl
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    public func handleCallback(_ url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "auth_attempt" })?.value,
              let id = UUID(uuidString: value) else { return }
        await complete(id: id, deviceCode: pendingAttempt?.deviceCode)
    }

    public func complete(id: UUID, deviceCode: String? = nil) async {
        state = .authorizing
        do {
            let session = try await account.completeAuth(id: id, deviceCode: deviceCode)
            pendingAttempt = nil
            state = .signedIn(session.profile)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func logout() async {
        pollingTask?.cancel()
        do { try await account.logout() } catch { /* Local sign-out still wins. */ }
        pendingAttempt = nil
        state = .signedOut
    }

    private func pollTV(_ attempt: AuthAttempt) {
        pollingTask = Task { [weak self, account] in
            let interval = max(attempt.pollingInterval ?? 5, 5)
            while !Task.isCancelled, Date() < attempt.expiresAt {
                do {
                    try await Task.sleep(for: .seconds(interval))
                    let status = try await account.authAttempt(id: attempt.attemptId, deviceCode: attempt.deviceCode)
                    if status == "approved" {
                        await self?.complete(id: attempt.attemptId, deviceCode: attempt.deviceCode)
                        return
                    }
                    if status == "denied" || status == "expired" {
                        self?.state = .signedOut
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self?.state = .failed(error.localizedDescription)
                    return
                }
            }
            self?.state = .signedOut
        }
    }
}

@MainActor
@Observable
public final class AdultContentController {
    public private(set) var isEnabled: Bool
    public private(set) var isUnlocked = false
    public private(set) var failedAttempts: Int
    public private(set) var lockUntil: Date?
    public private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let now: () -> Date
    private let prefix = "SmartMovie.AdultContent"

    public init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { .now }) {
        self.defaults = defaults
        self.now = now
        isEnabled = defaults.bool(forKey: "SmartMovie.AdultContent.Enabled")
        failedAttempts = defaults.integer(forKey: "SmartMovie.AdultContent.Failures")
        lockUntil = defaults.object(forKey: "SmartMovie.AdultContent.LockUntil") as? Date
        if let lockUntil, lockUntil <= now() {
            self.lockUntil = nil
            defaults.removeObject(forKey: "SmartMovie.AdultContent.LockUntil")
        }
    }

    public var includeAdult: Bool { isEnabled && isUnlocked && !isLocked }
    public var isLocked: Bool { lockUntil.map { $0 > now() } ?? false }

    public func configure(pin: String, confirmation: String) -> Bool {
        guard pin == confirmation, pin.range(of: #"^[0-9]{6}$"#, options: .regularExpression) != nil else {
            errorMessage = String(localized: "Enter the same six-digit PIN twice.", bundle: .module)
            return false
        }
        let salt = UUID().uuidString.lowercased()
        defaults.set(salt, forKey: "\(prefix).Salt")
        defaults.set(Self.digest(pin: pin, salt: salt), forKey: "\(prefix).Digest")
        defaults.set(true, forKey: "\(prefix).Enabled")
        defaults.set(0, forKey: "\(prefix).Failures")
        defaults.removeObject(forKey: "\(prefix).LockUntil")
        isEnabled = true
        isUnlocked = true
        failedAttempts = 0
        lockUntil = nil
        errorMessage = nil
        return true
    }

    public func unlock(pin: String) -> Bool {
        guard !isLocked else {
            errorMessage = String(localized: "Too many attempts. Try again in five minutes.", bundle: .module)
            return false
        }
        guard pin.range(of: #"^[0-9]{6}$"#, options: .regularExpression) != nil,
              let salt = defaults.string(forKey: "\(prefix).Salt"),
              let expected = defaults.string(forKey: "\(prefix).Digest"),
              Self.digest(pin: pin, salt: salt) == expected else {
            recordFailure()
            return false
        }
        failedAttempts = 0
        defaults.set(0, forKey: "\(prefix).Failures")
        isUnlocked = true
        errorMessage = nil
        return true
    }

    public func disable() {
        for suffix in ["Enabled", "Salt", "Digest", "Failures", "LockUntil"] {
            defaults.removeObject(forKey: "\(prefix).\(suffix)")
        }
        isEnabled = false
        isUnlocked = false
        failedAttempts = 0
        lockUntil = nil
        errorMessage = nil
    }

    public func lock() { isUnlocked = false }

    private func recordFailure() {
        failedAttempts += 1
        if failedAttempts >= 5 {
            let deadline = now().addingTimeInterval(5 * 60)
            lockUntil = deadline
            failedAttempts = 0
            defaults.set(deadline, forKey: "\(prefix).LockUntil")
            defaults.set(0, forKey: "\(prefix).Failures")
            errorMessage = String(localized: "Too many attempts. Try again in five minutes.", bundle: .module)
        } else {
            defaults.set(failedAttempts, forKey: "\(prefix).Failures")
            errorMessage = String(localized: "Incorrect PIN.", bundle: .module)
        }
    }

    private static func digest(pin: String, salt: String) -> String {
        SHA256.hash(data: Data("\(salt):\(pin)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
@Observable
public final class RegionSettings {
    public var override: String? {
        didSet {
            let normalized = override?.uppercased()
            if normalized != override { override = normalized; return }
            defaults.set(override, forKey: key)
        }
    }

    private let defaults: UserDefaults
    private let key = "SmartMovie.RegionOverride"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        override = defaults.string(forKey: key)
    }

    public var effectiveRegion: String {
        override ?? Locale.current.region?.identifier ?? "US"
    }
}

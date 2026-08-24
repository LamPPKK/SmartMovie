import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

public struct ProfileView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openURL) private var openURL
    @State private var pin = ""
    @State private var pinConfirmation = ""
    @State private var showLogoutChoice = false
    @State private var lists: [UserList] = []
    @State private var listsAccountID: Int?
    @State private var accountMessage: String?
    @State private var newListName = ""
    @State private var newListDescription = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                accountCard
                preferences
                if let accountID = signedInAccountID {
                    AccountRecommendationsView().id(accountID)
                    if listsAccountID == accountID {
                        accountLibrary
                    } else {
                        ProgressView()
                    }
                }
                NavigationLink { AboutView() } label: {
                    Label(String(localized: "About, privacy & attribution", bundle: .module), systemImage: "info.circle")
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(24)
        }
        .navigationTitle(String(localized: "Profile", bundle: .module))
        .cinemaScreen()
        .alert(String(localized: "Account", bundle: .module), isPresented: messageBinding) {
            Button(String(localized: "OK", bundle: .module), role: .cancel) {}
        } message: { Text(accountMessage ?? "") }
        .confirmationDialog(
            String(localized: "Keep your TMDb library on this device?", bundle: .module),
            isPresented: $showLogoutChoice,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Keep as local library", bundle: .module)) { Task { await logout(removeAccountData: false) } }
            Button(String(localized: "Remove account data", bundle: .module), role: .destructive) {
                Task { await logout(removeAccountData: true) }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        }
        .task(id: signedInAccountID) {
            listsAccountID = nil
            lists = []
            newListName = ""
            newListDescription = ""
            accountMessage = nil
            guard signedInAccountID != nil else { return }
            await container.syncAccountLibrary(language: LocaleResolver.tmdbLanguage(for: Locale.current))
            await loadLists(reportErrors: false)
        }
    }

    @ViewBuilder
    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(String(localized: "TMDb account", bundle: .module))
            switch container.accountSession.state {
            case .checking:
                ProgressView(String(localized: "Checking session…", bundle: .module))
            case .signedOut:
                Text(String(
                    localized: "Sign in through the TMDb website to sync favorites, watchlist, ratings, recommendations, and mixed lists.",
                    bundle: .module
                ))
                    .foregroundStyle(CinemaTheme.muted)
                signInButton
            case .authorizing:
                authorizationProgress
            case .signedIn(let profile):
                HStack(spacing: 16) {
                    RemoteArtwork(url: container.imageURL(path: profile.avatarPath, kind: .profile), kind: .profile)
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name.isEmpty ? profile.username : profile.name).font(.title2.bold())
                        Text("@\(profile.username)").foregroundStyle(CinemaTheme.muted)
                    }
                }
                Button(role: .destructive) { showLogoutChoice = true } label: {
                    Label(String(localized: "Sign out", bundle: .module), systemImage: "rectangle.portrait.and.arrow.right")
                }
            case .failed(let message):
                Text(message).foregroundStyle(CinemaTheme.accent)
                signInButton
            }
        }
        .padding(20)
        .background(CinemaTheme.surface, in: RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
    }

    private var signInButton: some View {
        Button {
            Task {
                #if os(tvOS)
                let mode = "tv"
                #else
                let mode = "browser"
                #endif
                guard let callback = URL(string: "smartmovie://auth/callback"),
                      let authorization = await container.accountSession.begin(returnURI: callback, mode: mode) else { return }
                openURL(authorization)
            }
        } label: {
            Label(String(localized: "Continue on TMDb", bundle: .module), systemImage: "person.badge.key")
        }
        .buttonStyle(.borderedProminent)
        .tint(CinemaTheme.accent)
        .disabled(container.capabilities?.supportsAccount("authentication") == false)
    }

    @ViewBuilder
    private var authorizationProgress: some View {
        if let attempt = container.accountSession.pendingAttempt {
            #if os(tvOS)
            QRCodeView(value: attempt.authorizationUrl.absoluteString)
                .frame(width: 260, height: 260)
                .accessibilityLabel(String(localized: "QR code to authorize SmartMovie on TMDb", bundle: .module))
            if let code = attempt.deviceCode {
                Text(code).font(.system(size: 42, weight: .black, design: .monospaced))
                Text(String(localized: "Scan the QR code and confirm this six-digit code.", bundle: .module))
                    .foregroundStyle(CinemaTheme.muted)
            }
            #else
            ProgressView(String(localized: "Complete approval in your browser…", bundle: .module))
            Button(String(localized: "Open browser again", bundle: .module)) { openURL(attempt.authorizationUrl) }
            #endif
        } else {
            ProgressView()
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(String(localized: "Catalog preferences", bundle: .module))
            Picker(String(localized: "Provider region", bundle: .module), selection: regionBinding) {
                Text(String(localized: "Device region", bundle: .module)).tag("")
                ForEach(Self.regions, id: \.self) { code in
                    Text(Locale.current.localizedString(forRegionCode: code) ?? code).tag(code)
                }
            }
            .pickerStyle(.menu)
            adultControls
        }
        .padding(20)
        .background(CinemaTheme.surface, in: RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
    }

    @ViewBuilder
    private var adultControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Adult content", bundle: .module), systemImage: "18.circle")
                .font(.headline)
            Text(String(
                // swiftlint:disable:next line_length
                localized: "Off by default. A six-digit PIN is stored only on this device. Adult titles never appear on Watch/Wear remote or public previews.",
                bundle: .module
            ))
                .font(.footnote)
                .foregroundStyle(CinemaTheme.muted)

            if !container.adultContent.isEnabled {
                SecureField(String(localized: "Six-digit PIN", bundle: .module), text: $pin)
                    .textContentType(.newPassword)
                SecureField(String(localized: "Confirm PIN", bundle: .module), text: $pinConfirmation)
                    .textContentType(.newPassword)
                Button(String(localized: "Enable adult content", bundle: .module)) {
                    if container.adultContent.configure(pin: pin, confirmation: pinConfirmation) {
                        pin = ""; pinConfirmation = ""
                    }
                }
            } else if container.adultContent.isUnlocked {
                Label(String(localized: "Unlocked on this device", bundle: .module), systemImage: "lock.open.fill")
                    .foregroundStyle(.green)
                HStack {
                    Button(String(localized: "Lock", bundle: .module)) { container.adultContent.lock() }
                    Button(String(localized: "Disable", bundle: .module), role: .destructive) { container.adultContent.disable() }
                }
            } else {
                SecureField(String(localized: "Enter PIN", bundle: .module), text: $pin)
                    .textContentType(.password)
                Button(String(localized: "Unlock", bundle: .module)) {
                    if container.adultContent.unlock(pin: pin) { pin = "" }
                }
            }
            if let error = container.adultContent.errorMessage {
                Text(error).font(.footnote).foregroundStyle(CinemaTheme.accent)
            }
        }
    }

    private var accountLibrary: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(String(localized: "Custom lists", bundle: .module))
            TextField(String(localized: "List name", bundle: .module), text: $newListName)
                .padding(10)
                .background(CinemaTheme.background, in: RoundedRectangle(cornerRadius: 10))
            TextField(String(localized: "Description", bundle: .module), text: $newListDescription, axis: .vertical)
                .padding(10)
                .background(CinemaTheme.background, in: RoundedRectangle(cornerRadius: 10))
                .lineLimit(2...4)
            Button {
                Task { await createList() }
            } label: {
                Label(String(localized: "Create list", bundle: .module), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(CinemaTheme.accent)
            .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if lists.isEmpty {
                Text(String(localized: "Your TMDb mixed movie and TV lists will appear here.", bundle: .module))
                    .foregroundStyle(CinemaTheme.muted)
            } else {
                ForEach(lists) { list in
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        NavigationLink {
                            AccountListDetailView(list: list)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(list.name).font(.headline)
                                if !list.description.isEmpty {
                                    Text(list.description).font(.caption).foregroundStyle(CinemaTheme.muted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await deleteList(list) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(String(localized: "Delete list", bundle: .module))
                    }
                }
            }
            Button(String(localized: "Refresh lists", bundle: .module)) {
                Task { await loadLists(reportErrors: true) }
            }
        }
    }

    private var signedInAccountID: Int? {
        guard case .signedIn(let profile) = container.accountSession.state else { return nil }
        return profile.id
    }

    private var regionBinding: Binding<String> {
        Binding(
            get: { container.regionSettings.override ?? "" },
            set: { container.regionSettings.override = $0.isEmpty ? nil : $0 }
        )
    }

    private var messageBinding: Binding<Bool> {
        Binding(get: { accountMessage != nil }, set: { if !$0 { accountMessage = nil } })
    }

    private func logout(removeAccountData: Bool) async {
        // Account-backed values are removed from the secure token store. The local
        // library remains usable; the sync repository applies the selected cleanup
        // policy when account-origin records are present.
        if let sync = container.library as? any LibrarySyncRepository {
            try? sync.deactivateAccount(removeAccountData: removeAccountData)
        }
        if removeAccountData { await container.removeAccountMutationData() }
        await container.accountSession.logout()
        lists = []
        listsAccountID = nil
    }

    @MainActor
    private func createList() async {
        guard let accountID = signedInAccountID else { return }
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let mutation = try await container.queueCreateList(
                name: String(name.prefix(100)),
                description: String(newListDescription.prefix(1_000)),
                isPublic: false,
                region: container.regionSettings.override ?? Locale.current.region?.identifier ?? "US",
                language: Locale.current.language.languageCode?.identifier ?? "en"
            )
            guard signedInAccountID == accountID else { return }
            if let localID = mutation.localListID {
                lists.append(UserList(
                    id: localID,
                    name: name,
                    description: newListDescription,
                    isPublic: false,
                    results: []
                ))
            }
            newListName = ""
            newListDescription = ""
            _ = await container.flushAccountOutbox()
            guard signedInAccountID == accountID else { return }
            await loadLists(reportErrors: false)
        } catch {
            if signedInAccountID == accountID { accountMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func deleteList(_ list: UserList) async {
        guard let accountID = signedInAccountID else { return }
        do {
            if list.id < 0 {
                try await container.cancelPendingList(localID: list.id)
            } else {
                _ = try await container.queueDeleteList(id: list.id)
            }
            guard signedInAccountID == accountID else { return }
            lists.removeAll { $0.id == list.id }
            if list.id >= 0 { _ = await container.flushAccountOutbox() }
        } catch {
            if signedInAccountID == accountID { accountMessage = error.localizedDescription }
        }
    }

    @MainActor
    private func loadLists(reportErrors: Bool) async {
        guard let accountID = signedInAccountID else {
            lists = []
            return
        }
        var remote = lists
        do {
            remote = try await loadAllUserLists { page in
                try await container.account.lists(page: page)
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            return
        } catch {
            guard signedInAccountID == accountID else { return }
            if reportErrors { accountMessage = error.localizedDescription }
        }
        guard signedInAccountID == accountID else { return }
        let pending = await container.pendingAccountMutations()
        guard signedInAccountID == accountID, !Task.isCancelled else { return }
        lists = applyPendingLists(remote, pending: pending)
        listsAccountID = accountID
    }

    private static let regions = ["US", "GB", "CA", "AU", "FR", "DE", "JP", "KR", "VN", "TW", "HK", "SG", "IN", "BR", "MX"]
}

private struct QRCodeView: View {
    let value: String

    var body: some View {
        if let image = Self.make(value) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
        } else {
            Image(systemName: "qrcode").font(.system(size: 120))
        }
    }

    private static func make(_ value: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent)
    }
}

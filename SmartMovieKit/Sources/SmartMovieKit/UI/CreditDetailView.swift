import SwiftUI

public struct CreditRoute: Hashable, Sendable {
    public let creditID: String
    public let label: String

    public init(creditID: String, label: String) {
        self.creditID = creditID
        self.label = label
    }
}

struct CreditShelf: View {
    @Environment(AppContainer.self) private var container
    let title: String
    let credits: [Credit]

    private var visibleCredits: [Credit] {
        CatalogAdultVisibility.credits(credits, includeAdult: container.adultContent.includeAdult)
    }

    var body: some View {
        if !visibleCredits.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(Array(visibleCredits.prefix(40).enumerated()), id: \.offset) { _, credit in
                            creditLink(credit)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func creditLink(_ credit: Credit) -> some View {
        if let creditID = credit.creditId {
            NavigationLink(value: CreditRoute(
                creditID: creditID,
                label: credit.title ?? String(localized: "Credit details", bundle: .module)
            )) {
                creditCard(credit)
            }
            .catalogNavigationButtonStyle()
        } else if let title = fallbackTitle(credit) {
            NavigationLink(value: title) { creditCard(credit) }
                .catalogNavigationButtonStyle()
        } else if let person = fallbackPerson(credit) {
            NavigationLink(value: CatalogEntity.person(person)) { creditCard(credit) }
                .catalogNavigationButtonStyle()
        } else {
            creditCard(credit)
        }
    }

    private func creditCard(_ credit: Credit) -> some View {
        let profile = credit.mediaType == nil
        return VStack(alignment: .leading, spacing: 8) {
            RemoteArtwork(
                url: container.imageURL(
                    path: profile ? credit.profilePath : credit.posterPath,
                    kind: profile ? .profile : .poster
                ),
                kind: profile ? .profile : .poster
            )
            .frame(width: 116, height: profile ? 148 : 172)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Text(credit.title ?? String(localized: "Credit details", bundle: .module))
                .font(.caption.weight(.semibold))
                .foregroundStyle(CinemaTheme.foreground)
                .lineLimit(2)
            if let role = credit.roleName {
                Text(role).font(.caption2).foregroundStyle(CinemaTheme.muted).lineLimit(2)
            }
        }
        .frame(width: 116, alignment: .leading)
    }

    private func fallbackTitle(_ credit: Credit) -> TitleSummary? {
        guard let id = credit.id, let mediaType = credit.mediaType, let title = credit.title else { return nil }
        return TitleSummary(
            id: id,
            mediaType: mediaType,
            title: title,
            originalTitle: title,
            overview: "",
            posterPath: credit.posterPath,
            isAdult: credit.adult == true
        )
    }

    private func fallbackPerson(_ credit: Credit) -> PersonSummary? {
        guard let id = credit.id, let name = credit.title else { return nil }
        return PersonSummary(
            id: id,
            name: name,
            profilePath: credit.profilePath,
            knownForDepartment: credit.department,
            popularity: 0,
            knownFor: []
        )
    }
}

public struct CreditDetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.locale) private var locale
    @State private var state: Loadable<CreditDetail> = .idle
    private let route: CreditRoute

    private var includeAdult: Bool { container.adultContent.includeAdult }
    private var loadKey: String {
        "\(route.creditID):\(LocaleResolver.tmdbLanguage(for: locale)):\(includeAdult)"
    }

    public init(route: CreditRoute) { self.route = route }

    public var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                StateMessageView(
                    icon: "person.text.rectangle",
                    title: String(localized: "Credit unavailable", bundle: .module),
                    message: message,
                    retry: { Task { await load() } }
                )
            case .loaded(let detail):
                content(detail)
            }
        }
        .navigationTitle(String(localized: "Credit details", bundle: .module))
        .inlineNavigationTitle()
        .cinemaScreen()
        .task(id: loadKey) { await load() }
    }

    private func content(_ detail: CreditDetail) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let person = detail.personSummary {
                    NavigationLink(value: CatalogEntity.person(person)) {
                        personCard(person)
                    }
                    .catalogNavigationButtonStyle()
                }
                roleSection(detail)
                if let title = detail.titleSummary, includeAdult || !title.isAdult {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(String(localized: "Title", bundle: .module))
                        NavigationLink(value: title) { PosterCard(title: title) }
                            .catalogNavigationButtonStyle()
                    }
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(24)
        }
    }

    private func personCard(_ person: PersonSummary) -> some View {
        HStack(spacing: 18) {
            RemoteArtwork(url: container.imageURL(path: person.profilePath, kind: .profile), kind: .profile)
                .frame(width: 130, height: 174)
                .clipShape(RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(String(localized: "Person", bundle: .module))
                Text(person.name).font(.system(.title, design: .serif, weight: .bold))
                if let department = person.knownForDepartment {
                    Text(department).foregroundStyle(CinemaTheme.accent)
                }
            }
        }
    }

    private func roleSection(_ detail: CreditDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(String(localized: "Role", bundle: .module))
            if let character = detail.character {
                LabeledContent(String(localized: "Character", bundle: .module), value: character)
            }
            if let job = detail.job { LabeledContent(String(localized: "Job", bundle: .module), value: job) }
            if let department = detail.department {
                LabeledContent(String(localized: "Department", bundle: .module), value: department)
            }
        }
        .foregroundStyle(CinemaTheme.foreground)
    }

    @MainActor
    private func load() async {
        guard let catalog = container.catalog as? any CatalogV2Repository else {
            state = .failed(String(localized: "This server does not support detailed catalog entities yet.", bundle: .module))
            return
        }
        state = .loading
        let expectedLoadKey = loadKey
        let requestAllowsAdult = includeAdult
        do {
            let detail = try await catalog.credit(
                id: route.creditID,
                language: LocaleResolver.tmdbLanguage(for: locale),
                includeAdult: requestAllowsAdult
            )
            guard !Task.isCancelled, loadKey == expectedLoadKey else { return }
            state = .loaded(detail.applyingAdultVisibility(includeAdult: requestAllowsAdult))
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

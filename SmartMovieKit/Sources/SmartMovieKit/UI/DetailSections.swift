import SwiftUI

extension DetailView {
    func overview(_ detail: TitleDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(String(localized: "Story", bundle: .module))
            Text(detail.overview.isEmpty ? String(localized: "No overview is available.", bundle: .module) : detail.overview)
                .font(.body)
                .foregroundStyle(CinemaTheme.foreground.opacity(0.84))
                .lineSpacing(5)
            if let status = detail.status {
                LabeledContent(String(localized: "Status", bundle: .module), value: status)
                    .foregroundStyle(CinemaTheme.muted)
            }
        }
        .padding(.horizontal, 24)
    }

    func castShelf(_ cast: [CastMember]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(String(localized: "Cast", bundle: .module)).padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(cast.prefix(20)) { member in
                        NavigationLink(value: personEntity(member)) {
                            VStack(spacing: 9) {
                                RemoteArtwork(
                                    url: container.imageURL(path: member.profilePath, kind: .profile),
                                    kind: .profile
                                )
                                .frame(width: 104, height: 132)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                Text(member.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CinemaTheme.foreground)
                                    .lineLimit(2)
                                if let character = member.character {
                                    Text(character)
                                        .font(.caption2)
                                        .foregroundStyle(CinemaTheme.muted)
                                        .lineLimit(2)
                                }
                            }
                            .frame(width: 110)
                        }
                        .catalogNavigationButtonStyle()
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    func similarShelf(_ similar: [TitleSummary]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(String(localized: "More like this", bundle: .module)).padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(similar) { title in
                        NavigationLink(value: title) { PosterCard(title: title) }
                            .catalogNavigationButtonStyle()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    var credits: some View {
        NavigationLink {
            AboutView()
        } label: {
            Label(String(localized: "About & Credits", bundle: .module), systemImage: "info.circle")
                .foregroundStyle(CinemaTheme.muted)
                .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    func deepSections(_ detail: TitleDetailV2) -> some View {
        if !detail.tagline.isEmpty {
            Text("“\(detail.tagline)”")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .italic()
                .foregroundStyle(CinemaTheme.muted)
                .padding(.horizontal, 24)
        }

        if let collection = detail.collection {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(String(localized: "Collection", bundle: .module))
                NavigationLink(value: CatalogEntity.collection(collection)) {
                    Label(collection.name, systemImage: "rectangle.stack.fill")
                        .font(.headline)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CinemaTheme.surface, in: RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
        }

        if !detail.seasons.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(String(localized: "Seasons & episodes", bundle: .module))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(detail.seasons) { season in
                            NavigationLink(value: SeasonRoute(seriesID: detail.id, season: season)) {
                                CatalogEntityCard(entity: .season(season))
                            }
                            .catalogNavigationButtonStyle()
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }

        if let offers = detail.watchProviders.first(where: { $0.region == container.regionSettings.effectiveRegion }),
           !offers.stream.isEmpty || !offers.rent.isEmpty || !offers.buy.isEmpty || !offers.free.isEmpty || !offers.ads.isEmpty {
            providerSection(offers)
        }

        if !detail.reviews.results.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(String(localized: "Reviews", bundle: .module))
                ForEach(detail.reviews.results.prefix(4)) { review in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(review.author).font(.headline)
                            Spacer()
                            if let rating = review.rating { RatingBadge(rating: rating) }
                        }
                        Text(review.content).lineLimit(8).foregroundStyle(CinemaTheme.muted)
                    }
                    .padding(16)
                    .background(CinemaTheme.surface, in: RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
                }
            }
            .padding(.horizontal, 24)
        }

        if !detail.recommendations.results.isEmpty {
            similarShelf(detail.recommendations.results)
        }
    }

    func providerSection(_ region: ProviderRegion) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(String(localized: "Where to watch", bundle: .module))
            providerRow(String(localized: "Stream", bundle: .module), values: region.stream + region.free + region.ads)
            providerRow(String(localized: "Rent", bundle: .module), values: region.rent)
            providerRow(String(localized: "Buy", bundle: .module), values: region.buy)
            HStack {
                Text(String(localized: "Availability data by JustWatch", bundle: .module))
                    .font(.footnote).foregroundStyle(CinemaTheme.muted)
                Spacer()
                if let value = region.tmdbUrl,
                   let url = URL(string: value),
                   url.host?.hasSuffix("themoviedb.org") == true {
                    Button(String(localized: "View on TMDb", bundle: .module)) { openURL(url) }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    func providerRow(_ title: String, values: [ProviderOffer]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(values) { provider in
                            HStack(spacing: 8) {
                                RemoteArtwork(
                                    url: container.imageURL(path: provider.logoPath, kind: .profile),
                                    kind: .profile
                                )
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(provider.providerName).font(.caption.weight(.semibold))
                            }
                            .padding(8)
                            .background(CinemaTheme.surface, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    func personEntity(_ member: CastMember) -> CatalogEntity {
        .person(PersonSummary(
            id: member.id,
            name: member.name,
            profilePath: member.profilePath,
            knownForDepartment: nil,
            popularity: 0,
            knownFor: []
        ))
    }

    func runtimeText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remaining = minutes % 60
        return hours > 0 ? "\(hours)h \(remaining)m" : "\(remaining)m"
    }
}

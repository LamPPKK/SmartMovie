import SwiftUI

enum CatalogEditorialPresentation {
    static func reviews(_ values: [Review], limit: Int = 4) -> [Review] {
        var seen = Set<String>()
        return values.filter { review in
            !review.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && seen.insert(review.id).inserted
        }
        .prefix(limit)
        .map(\.self)
    }

    static func titles(
        _ values: [TitleSummary],
        excluding currentLibraryKey: String? = nil,
        includeAdult: Bool = false,
        limit: Int = 20
    ) -> [TitleSummary] {
        var seen = Set<String>()
        return values.filter { title in
            (includeAdult || !title.isAdult)
                && title.libraryKey != currentLibraryKey
                && seen.insert(title.libraryKey).inserted
        }
        .prefix(limit)
        .map(\.self)
    }
}

struct CatalogReviewSection: View {
    let reviews: [Review]

    private var presentedReviews: [Review] {
        CatalogEditorialPresentation.reviews(reviews)
    }

    var body: some View {
        if !presentedReviews.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(String(localized: "Reviews", bundle: .module))
                ForEach(presentedReviews) { review in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(author(for: review))
                                    .font(.headline)
                                if let createdAt = review.createdAt {
                                    Text(String(createdAt.prefix(10)))
                                        .font(.caption)
                                        .foregroundStyle(CinemaTheme.muted)
                                }
                            }
                            Spacer()
                            if let rating = review.rating {
                                RatingBadge(rating: rating)
                            }
                        }
                        Text(review.content)
                            .foregroundStyle(CinemaTheme.muted)
                            .lineSpacing(3)
                    }
                    .padding(16)
                    .background(CinemaTheme.surface, in: RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func author(for review: Review) -> String {
        let author = review.author.trimmingCharacters(in: .whitespacesAndNewlines)
        return author.isEmpty ? String(localized: "TMDb member", bundle: .module) : author
    }
}

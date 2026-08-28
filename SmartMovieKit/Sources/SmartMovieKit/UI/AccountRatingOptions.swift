import SwiftUI

/// Shared Movie/TV/Episode menu content; a nil selection removes the rating.
struct AccountRatingOptions: View {
    @Environment(\.locale) private var locale
    let currentRating: Double?
    let onSelect: (Double?) -> Void

    static let values = (1...20).map { Double($0) / 2 }

    static func label(for value: Double, locale: Locale) -> String {
        let score = value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return "\(score) / 10"
    }

    var body: some View {
        ForEach(Self.values, id: \.self) { value in
            Button(Self.label(for: value, locale: locale)) { onSelect(value) }
        }
        if currentRating != nil {
            Button(String(localized: "Remove rating", bundle: .module), role: .destructive) {
                onSelect(nil)
            }
        }
    }
}

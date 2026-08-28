import SwiftUI

struct AdaptiveDetailGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Measure the complete labels before deciding whether a row fits.
            HStack(spacing: 12, content: content)
                .fixedSize(horizontal: true, vertical: true)
            VStack(alignment: .leading, spacing: 12, content: content)
        }
    }
}

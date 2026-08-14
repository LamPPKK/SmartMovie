import SwiftUI

struct WatchRemoteView: View {
    @Bindable var model: WatchRemoteModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.02, blue: 0.05),
                    Color(red: 0.01, green: 0.01, blue: 0.015)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()

            if let title = model.currentTitle {
                remoteContent(title)
            } else {
                emptyContent
            }
        }
        .alert(
            String(localized: "SmartMovie Remote"),
            isPresented: Binding(
                get: { model.statusMessage != nil },
                set: { if !$0 { model.clearStatus() } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                model.clearStatus()
            }
        } message: {
            Text(model.statusMessage ?? "")
        }
    }

    private func remoteContent(_ title: WatchRemoteTitle) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                artwork(title)
                titleMetadata(title)
                primaryControls(title)
                libraryControls(title)
                connectionStatus
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }

    private func artwork(_ title: WatchRemoteTitle) -> some View {
        AsyncImage(url: title.artworkURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "film.stack.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Label(String(format: "%.1f", title.rating), systemImage: "star.fill")
                .font(.caption2.bold())
                .foregroundStyle(.yellow)
                .padding(5)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(6)
        }
    }

    private func titleMetadata(_ title: WatchRemoteTitle) -> some View {
        VStack(spacing: 3) {
            Text(title.mediaType == "movie" ? String(localized: "MOVIE") : String(localized: "SERIES"))
                .font(.system(size: 9, weight: .black))
                .tracking(1.5)
                .foregroundStyle(.red)
            Text(title.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let year = title.year {
                Text(year)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func primaryControls(_ title: WatchRemoteTitle) -> some View {
        HStack(spacing: 8) {
            remoteButton(
                title: String(localized: "Trailer"),
                systemImage: "play.fill",
                disabled: !title.hasTrailer,
                action: model.playTrailer
            )
            remoteButton(
                title: String(localized: "Open"),
                systemImage: "iphone.gen3",
                disabled: false,
                action: model.openDetails
            )
        }
    }

    private func libraryControls(_ title: WatchRemoteTitle) -> some View {
        HStack(spacing: 8) {
            remoteButton(
                title: String(localized: "Favorite"),
                systemImage: title.isFavorite ? "heart.fill" : "heart",
                disabled: false,
                action: model.toggleFavorite
            )
            remoteButton(
                title: String(localized: "Watchlist"),
                systemImage: title.isWatchlisted ? "bookmark.fill" : "bookmark",
                disabled: false,
                action: model.toggleWatchlist
            )
        }
    }

    private func remoteButton(
        title: String,
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.body.bold())
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(disabled)
        .accessibilityLabel(title)
    }

    private var connectionStatus: some View {
        Label(
            model.isReachable ? String(localized: "iPhone connected") : String(localized: "Open iPhone app"),
            systemImage: model.isReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash"
        )
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(model.isReachable ? .green : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.06), in: Capsule())
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack.fill")
                .font(.system(size: 38, weight: .black))
                .foregroundStyle(.red)
            Text(String(localized: "SmartMovie Remote"))
                .font(.headline)
            Text(String(localized: "Open a title on your iPhone to start controlling it."))
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            connectionStatus
        }
        .padding()
    }
}

import SwiftUI

struct ActionPill: View {
    let title: String
    let systemImage: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(prominent ? CinemaTheme.accent : CinemaTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(CinemaTheme.foreground)
    }
}

public struct AboutView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "film.stack.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(CinemaTheme.accent)
                Text("SmartMovie")
                    .font(.system(.largeTitle, design: .serif, weight: .black))
                Text(String(localized: "A cinematic place to discover movies and television.", bundle: .module))
                    .foregroundStyle(CinemaTheme.muted)
                Text(String(localized: "Source repositories", bundle: .module))
                    .font(.title2.bold())
                Link("Smart Movie iOS", destination: URL(string: "https://github.com/LamPPKK/Smart-Movie-iOS")!)
                Link("Smart Movie Android", destination: URL(string: "https://github.com/LamPPKK/Smart-Movie-Android")!)
                Divider().overlay(.white.opacity(0.12))
                Text("TMDB")
                    .font(.title2.bold())
                    .foregroundStyle(Color(red: 0.01, green: 0.71, blue: 0.89))
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.footnote)
                    .foregroundStyle(CinemaTheme.muted)
                Link("The Movie Database", destination: URL(string: "https://www.themoviedb.org")!)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(28)
        }
        .navigationTitle(String(localized: "About & Credits", bundle: .module))
        .cinemaScreen()
    }
}

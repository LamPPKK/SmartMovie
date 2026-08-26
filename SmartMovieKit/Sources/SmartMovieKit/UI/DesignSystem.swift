import SwiftUI

public enum CinemaTheme {
    public static let background = Color(red: 0.02, green: 0.02, blue: 0.03)
    public static let elevated = Color(red: 0.055, green: 0.055, blue: 0.07)
    public static let surface = Color.white.opacity(0.07)
    public static let accent = Color(red: 0.88, green: 0.11, blue: 0.28)
    public static let gold = Color(red: 0.96, green: 0.71, blue: 0.20)
    public static let foreground = Color(red: 0.96, green: 0.97, blue: 0.99)
    public static let muted = Color(red: 0.58, green: 0.60, blue: 0.66)
    public static let cornerRadius: CGFloat = 18
}

public struct CinemaBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            CinemaTheme.background
            RadialGradient(
                colors: [CinemaTheme.accent.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 520
            )
            LinearGradient(
                colors: [.clear, Color(red: 0.03, green: 0.04, blue: 0.09).opacity(0.45)],
                startPoint: .top,
                endPoint: .bottomLeading
            )
        }
        .ignoresSafeArea()
    }
}

public struct SectionTitle: View {
    private let title: String

    public init(_ title: String) { self.title = title }

    public var body: some View {
        Text(title)
            .font(.system(.title2, design: .serif, weight: .bold))
            .foregroundStyle(CinemaTheme.foreground)
            .accessibilityAddTraits(.isHeader)
    }
}

public struct RatingBadge: View {
    private let rating: Double

    public init(rating: Double) { self.rating = rating }

    public var body: some View {
        Label(String(format: "%.1f", rating), systemImage: "star.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(CinemaTheme.gold)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.62), in: Capsule())
            .accessibilityLabel(String(localized: "Rating", bundle: .module))
            .accessibilityValue(String(format: "%.1f", rating))
    }
}

public struct LoadingPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false

    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: CinemaTheme.cornerRadius)
            .fill(CinemaTheme.surface)
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(glowing ? 0.14 : 0.03), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    glowing = true
                }
            }
            .accessibilityHidden(true)
    }
}

public struct StateMessageView: View {
    private let icon: String
    private let title: String
    private let message: String?
    private let retry: (() -> Void)?

    public init(icon: String, title: String, message: String? = nil, retry: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            if let message { Text(message) }
        } actions: {
            if let retry {
                Button(String(localized: "Try again", bundle: .module), action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(CinemaTheme.accent)
            }
        }
        .foregroundStyle(CinemaTheme.foreground)
    }
}

public extension View {
    func cinemaScreen() -> some View {
        background { CinemaBackground() }
            .preferredColorScheme(.dark)
            .tint(CinemaTheme.accent)
    }

    @ViewBuilder
    func homeTitleDisplayMode() -> some View {
        #if os(iOS)
        toolbarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func catalogSearchInputBehavior() -> some View {
        #if os(iOS) || os(tvOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func catalogTextFieldStyle() -> some View {
        #if os(tvOS)
        self
        #else
        textFieldStyle(.roundedBorder)
        #endif
    }

    @ViewBuilder
    func catalogNavigationButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain)
        #endif
    }
}

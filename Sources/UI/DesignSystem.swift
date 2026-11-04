import SwiftUI
import AppKit

// MARK: - Brand marks

struct BrandMark: View {
    let provider: ProviderID
    var size: CGFloat = 34
    var muted: Bool = false

    var body: some View {
        let spec = provider.spec
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(spec.gradient)
            ProviderGlyphView(provider: provider)
                .foregroundStyle(.white)
                .frame(width: size * 0.54, height: size * 0.54)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: spec.tint.opacity(muted ? 0 : 0.35), radius: size * 0.18, y: size * 0.05)
    }
}

struct ProviderGlyphView: View {
    let provider: ProviderID

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            glyph(side: side)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func glyph(side: CGFloat) -> some View {
        switch provider {
        case .telegram:
            PlaneGlyph().fill(style: FillStyle(eoFill: true))
        case .messenger:
            BoltGlyph().fill(style: FillStyle(eoFill: true))
        case .zalo:
            letter("Z", side: side)
        case .whatsapp:
            ZStack {
                Circle().strokeBorder(Color.white, lineWidth: side * 0.14)
                Image(systemName: "phone.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: side * 0.44, height: side * 0.44)
            }
            .frame(width: side * 0.92, height: side * 0.92)
        case .discord:
            DiscordGlyph().fill(style: FillStyle(eoFill: true))
        case .slack:
            symbol("number", side: side)
        case .instagram:
            InstagramGlyph()
        case .teams:
            letter("T", side: side)
        case .custom:
            symbol("link", side: side)
        }
    }

    /// A single letter, scaled to the glyph box instead of relying on a fixed point size.
    private func letter(_ text: String, side: CGFloat) -> some View {
        Text(text)
            .font(.system(size: side * 1.02, weight: .heavy, design: .rounded))
            .lineLimit(1)
            // `fixedSize` keeps the glyph at its real size instead of letting a tight frame
            // shrink it; the leftover line-height overflow is invisible.
            .fixedSize()
            .frame(width: side, height: side)
    }

    /// SF Symbols ignore `minimumScaleFactor`; they have to be resized explicitly or they overflow.
    private func symbol(_ name: String, side: CGFloat) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .frame(width: side * 0.76, height: side * 0.76)
    }
}

private struct PlaneGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let p = NormalizedPath(rect)
        var path = Path()
        path.move(to: p(0.92, 0.10))
        path.addLine(to: p(0.04, 0.47))
        path.addLine(to: p(0.36, 0.59))
        path.addLine(to: p(0.44, 0.92))
        path.addLine(to: p(0.60, 0.64))
        path.addLine(to: p(0.92, 0.10))
        path.closeSubpath()
        // Window of the plane, punched out for a little depth.
        path.move(to: p(0.36, 0.59))
        path.addLine(to: p(0.86, 0.24))
        path.addLine(to: p(0.44, 0.92))
        path.closeSubpath()
        return path
    }
}

private struct BoltGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let p = NormalizedPath(rect)
        var path = Path()
        path.move(to: p(0.64, 0.02))
        path.addLine(to: p(0.10, 0.56))
        path.addLine(to: p(0.42, 0.56))
        path.addLine(to: p(0.34, 0.98))
        path.addLine(to: p(0.90, 0.42))
        path.addLine(to: p(0.56, 0.42))
        path.closeSubpath()
        return path
    }
}

private struct DiscordGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let p = NormalizedPath(rect)
        var path = Path()
        // A rounded "mask" with two punched-out eyes.
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.18,
                                      width: rect.width * 0.88, height: rect.height * 0.64),
                            cornerSize: CGSize(width: rect.width * 0.30, height: rect.height * 0.30))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.40,
                                   width: rect.width * 0.16, height: rect.height * 0.18))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.60, y: rect.minY + rect.height * 0.40,
                                   width: rect.width * 0.16, height: rect.height * 0.18))
        _ = p
        return path
    }
}

private struct InstagramGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.28, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: s * 0.10)
                Circle()
                    .strokeBorder(Color.white, lineWidth: s * 0.10)
                    .frame(width: s * 0.46, height: s * 0.46)
                Circle()
                    .fill(Color.white)
                    .frame(width: s * 0.10, height: s * 0.10)
                    .offset(x: s * 0.26, y: -s * 0.26)
            }
            .frame(width: s, height: s)
        }
    }
}

private struct NormalizedPath {
    let rect: CGRect
    init(_ rect: CGRect) { self.rect = rect }
    func callAsFunction(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }
}

// MARK: - Glass surfaces

struct GlassBubble<Content: View>: View {
    var corner: CGFloat = 26
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.42))
                    if let tint {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(tint.opacity(0.07))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.38), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: - Controls

struct BubbleIconButton: View {
    let systemName: String
    var size: CGFloat = 26
    var help: String = ""
    var tint: Color = .secondary
    var action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(hover ? Color.primary : tint)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(Color.primary.opacity(hover ? 0.10 : 0.001))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                )
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = .primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(tint.opacity(configuration.isPressed ? 0.6 : 0.95))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.07))
            )
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Small parts

struct UnreadBadge: View {
    let count: Int
    var compact: Bool = false

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: compact ? 9.5 : 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, compact ? 4.5 : 6)
                .frame(minWidth: compact ? 16 : 19, minHeight: compact ? 16 : 19)
                .background(Capsule().fill(Color(red: 0.98, green: 0.26, blue: 0.30)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
    }
}

struct AccountAvatar: View {
    let account: Account
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle().fill(account.provider.spec.gradient)
            Text(account.initial)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if account.status == .needsSignIn {
                Circle()
                    .fill(Color.orange)
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                    .offset(x: size * 0.35, y: size * 0.35)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 1))
    }
}

struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: color.opacity(0.8), radius: 3)
    }
}

// MARK: - Text styles

extension Font {
    static func bubbleTitle(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func bubbleBody(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .rounded)
    }
    static func bubbleCaption(_ size: CGFloat = 10.5) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
}

// MARK: - Haptics / feedback

enum Feedback {
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

// MARK: - Bubble background

struct BubbleBackground: View {
    var corner: CGFloat = 26
    var tint: Color? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.34))
            if let tint {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(tint.opacity(0.06))
            }
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.36), Color.white.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

extension View {
    func bubbleBackground(corner: CGFloat = 26, tint: Color? = nil) -> some View {
        self
            .background(BubbleBackground(corner: corner, tint: tint))
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

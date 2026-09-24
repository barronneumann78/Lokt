import SwiftUI
import UIKit

// User-selectable accent scheme. Volt is the default and the app's signature.
// Every alternative stays inside the allowed warm→green→teal band (blue/purple
// remain banned) and is bright enough that the near-black label used on accent
// fills (`PrimaryButtonStyle`, sent chat bubbles) stays legible — all schemes
// clear a 7:1 contrast ratio against `#0B0B0C`.
enum AccentScheme: String, CaseIterable, Identifiable {
    case volt
    case ember
    case mint
    case gold
    case tide
    case ice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .volt: return "Volt"
        case .ember: return "Ember"
        case .mint: return "Mint"
        case .gold: return "Gold"
        case .tide: return "Tide"
        case .ice: return "Ice"
        }
    }

    var color: Color {
        switch self {
        case .volt: return Color(red: 0.839, green: 1.0, blue: 0.247)   // #D6FF3F
        case .ember: return Color(red: 1.0, green: 0.580, blue: 0.251)  // #FF9440
        case .mint: return Color(red: 0.275, green: 0.902, blue: 0.639) // #46E6A3
        case .gold: return Color(red: 0.965, green: 0.788, blue: 0.290) // #F6C94A
        case .tide: return Color(red: 0.239, green: 0.863, blue: 0.765) // #3DDCC3
        case .ice: return Color(red: 0.957, green: 0.957, blue: 0.961)  // #F4F4F5
        }
    }

    /// Pill-gradient stops for the primary action: a lighter tint (top-leading)
    /// running into a darker shade (bottom-trailing) of the same accent. Every
    /// pair keeps light > base > dark in luminance and the near-black label at
    /// >= 5.9:1 on the dark stop (`harness/logic-checks/accent-gradient-stops`).
    var gradientStops: (light: Color, dark: Color) {
        switch self {
        case .volt: return (Color(red: 0.922, green: 1.0, blue: 0.451), Color(red: 0.659, green: 0.831, blue: 0.0))     // #EBFF73 → #A8D400
        case .ember: return (Color(red: 1.0, green: 0.682, blue: 0.420), Color(red: 0.851, green: 0.443, blue: 0.122))  // #FFAE6B → #D9711F
        case .mint: return (Color(red: 0.494, green: 0.941, blue: 0.749), Color(red: 0.133, green: 0.722, blue: 0.486)) // #7EF0BF → #22B87C
        case .gold: return (Color(red: 1.0, green: 0.867, blue: 0.478), Color(red: 0.851, green: 0.647, blue: 0.125))   // #FFDD7A → #D9A520
        case .tide: return (Color(red: 0.471, green: 0.918, blue: 0.839), Color(red: 0.122, green: 0.702, blue: 0.612)) // #78EAD6 → #1FB39C
        case .ice: return (Color(red: 1.0, green: 1.0, blue: 1.0), Color(red: 0.831, green: 0.831, blue: 0.847))        // #FFFFFF → #D4D4D8
        }
    }

    /// Alpha of the pill glow (shadow color = the dark stop). Ice is near-white,
    /// so its glow would read as a gray smear at full strength — keep it faint.
    var glowOpacity: Double {
        switch self {
        case .ice: return 0.22
        case .volt, .ember, .mint, .gold, .tide: return 0.5
        }
    }

    static let storageKey = "accentScheme"

    /// Missing or unrecognized stored value → volt, so a fresh install (or a
    /// rollback across scheme renames) always lands on the default.
    static func stored(from defaults: UserDefaults = .standard) -> AccentScheme {
        guard let raw = defaults.string(forKey: storageKey),
              let scheme = AccentScheme(rawValue: raw) else { return .volt }
        return scheme
    }
}

// Dark athletic minimal: near-black canvas, one volt accent, hairline-separated
// flat surfaces, oversized tabular numbers. Depth comes from glow and highlight
// only — never from new colors — and it lives EXCLUSIVELY here: this file is
// the one place `LinearGradient`/`RadialGradient`/`.shadow(` may appear
// (`harness/checks.sh` sensor 1b). Views reach depth through the tokens below:
// `primaryGradient` + `.primaryGlow()` (the one primary pill per screen),
// `cardHighlight` (inside `glassCard()`), `.heroGlow()` (the hero number),
// `chartFill` (the area under the Analytics progression line).
enum AppTheme {
    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 20
    static let rowPadding: CGFloat = 16
    static let cardCornerRadius: CGFloat = 22
    static let rowCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 14

    // Surfaces — near-black, flat.
    static let backgroundTop = Color(red: 0.043, green: 0.043, blue: 0.047)    // #0B0B0C
    static let backgroundBottom = Color(red: 0.043, green: 0.043, blue: 0.047) // same → flat
    static let card = Color(red: 0.078, green: 0.078, blue: 0.086)             // #141416
    static let surface = Color(red: 0.078, green: 0.078, blue: 0.086)
    static let surfaceElevated = Color(red: 0.110, green: 0.110, blue: 0.122)  // #1C1C1F
    static let fieldBackground = Color(red: 0.110, green: 0.110, blue: 0.122)
    static let mutedFill = Color.white.opacity(0.06)
    static let cardBorder = Color(red: 0.149, green: 0.149, blue: 0.165)       // #26262A hairline

    // THE accent — user-selectable scheme, volt lime by default. Primary
    // action + live/active state only. Cached so per-frame token reads never
    // hit `UserDefaults`; `ThemeStore.select` is the only writer.
    private static var activeScheme = AccentScheme.stored()
    static var accentScheme: AccentScheme { activeScheme }
    static func setAccentScheme(_ scheme: AccentScheme) { activeScheme = scheme }

    static var primary: Color { activeScheme.color }
    static var accent: Color { activeScheme.color }   // = primary, always

    // Primary-action pill: the accent's light stop running into its dark stop
    // at 135° (top-leading → bottom-trailing). Follows the chosen scheme.
    static var primaryGradient: LinearGradient {
        let stops = activeScheme.gradientStops
        return LinearGradient(colors: [stops.light, stops.dark],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Soft glow under the primary pill: the gradient's dark stop at ~½ alpha,
    /// dropped down so it reads as light spilling off the pill.
    struct Glow {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }
    static var primaryGlow: Glow {
        Glow(color: activeScheme.gradientStops.dark.opacity(activeScheme.glowOpacity),
             radius: 14, y: 8)
    }

    /// Glow under a small accent-filled data mark — Home's "today" bar in the
    /// week strip (phase 2). Same dark-stop color as the pill glow, tighter
    /// and fainter so a 30pt bar reads lit rather than smeared.
    static var barGlow: Glow {
        Glow(color: activeScheme.gradientStops.dark.opacity(activeScheme.glowOpacity * 0.7),
             radius: 6, y: 2)
    }

    /// Soft halo around the logger's red recording dot (phase 3): `danger` at
    /// ~55% alpha, tight radius, no offset — a glow, not a drop shadow.
    static let recordingGlow = Glow(color: danger.opacity(0.55), radius: 4, y: 0)

    /// Fill of the logger's ACTIVE set row: the accent at 7% over the row
    /// surface, paired with an accent hairline. State encoding, not chrome.
    static var activeRowTint: Color { activeScheme.color.opacity(0.07) }

    /// Accent hairline at 30%: the coach draft card's border (phase 4) — the
    /// one card on that screen whose chrome carries the accent.
    static var accentHairline: Color { activeScheme.color.opacity(0.3) }

    /// Fill of an accent-tinted capsule chip whose label is the accent —
    /// the coach's "1 OF 2" pager chip (phase 4), the Analytics metric chip.
    static var accentChipFill: Color { activeScheme.color.opacity(0.12) }

    /// Soft accent fill under the Analytics progression line (phase 5): the
    /// accent at 32% at the line fading to nothing at the baseline, top to
    /// bottom. Data depth, not chrome — the line itself stays the accent.
    static var chartFill: LinearGradient {
        LinearGradient(colors: [activeScheme.color.opacity(0.32), activeScheme.color.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// 1px inner top highlight on cards (Whoop-style depth) — sits inside the
    /// `cardBorder` hairline and fades out down the sides.
    static let cardHighlight = Color.white.opacity(0.04)

    /// Faint radial accent glow behind a hero number: accent at 14% fading to
    /// nothing, ~1.4× the number's width.
    static let heroGlowOpacity: Double = 0.14
    static let heroGlowSpread: CGFloat = 1.4

    // Semantic colors — fixed, never restyled by the accent scheme.
    static let secondary = Color(red: 1.0, green: 0.722, blue: 0.302)  // #FFB84D warn/amber
    static let success = Color(red: 0.247, green: 0.878, blue: 0.541)  // #3FE08A good
    static let danger = Color(red: 1.0, green: 0.361, blue: 0.361)     // #FF5C5C

    static let textPrimary = Color(red: 0.957, green: 0.957, blue: 0.961)   // #F4F4F5
    static let textSecondary = Color(red: 0.604, green: 0.604, blue: 0.635) // #9A9AA2
    static let textTertiary = Color(red: 0.369, green: 0.369, blue: 0.400)  // #5E5E66

    // Categorical chart palette — DATA ENCODING ONLY (series identity), never UI
    // chrome. Six hues laddered by lightness inside the allowed warm→green→teal
    // band (blue/purple stay banned), validated against #141416 for contrast and
    // color-vision separation (worst adjacent pair ΔE 12.3 CVD / 16.6 normal).
    // Slot order: volt, teal, gold, green, orange, coral.
    static let chartCategorical: [Color] = [
        Color(red: 0.839, green: 1.0, blue: 0.247),   // #D6FF3F volt
        Color(red: 0.184, green: 0.710, blue: 0.651), // #2FB5A6 teal
        Color(red: 0.965, green: 0.788, blue: 0.290), // #F6C94A gold
        Color(red: 0.122, green: 0.541, blue: 0.298), // #1F8A4C green
        Color(red: 1.0, green: 0.580, blue: 0.251),   // #FF9440 orange
        Color(red: 0.910, green: 0.282, blue: 0.247)  // #E8483F coral
    ]
    /// Neutral series color for "Other" / folded tails.
    static let chartNeutral = Color(red: 0.557, green: 0.557, blue: 0.588)  // #8E8E96
}

/// UIKit appearance proxies for nav bar, tab bar, and text inputs. Proxies
/// capture concrete colors at apply time, so this runs once at launch and
/// again on every accent-scheme change; bars created after a re-apply (the
/// scheme-commit rebuild recreates them) pick up the fresh accent.
enum AppChrome {
    static func apply() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AppTheme.backgroundTop)
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor(AppTheme.textPrimary)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(AppTheme.textPrimary)]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
        navigationBar.tintColor = UIColor(AppTheme.textPrimary)

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(AppTheme.backgroundTop)
        tabBarAppearance.shadowColor = UIColor(AppTheme.cardBorder)

        let normalColor = UIColor(AppTheme.textSecondary)
        let selectedColor = UIColor(AppTheme.primary)

        [tabBarAppearance.stackedLayoutAppearance,
         tabBarAppearance.inlineLayoutAppearance,
         tabBarAppearance.compactInlineLayoutAppearance].forEach { itemAppearance in
            itemAppearance.normal.iconColor = normalColor
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
            itemAppearance.selected.iconColor = selectedColor
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        }

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tabBarAppearance
        tabBar.scrollEdgeAppearance = tabBarAppearance
        tabBar.tintColor = selectedColor
        tabBar.unselectedItemTintColor = normalColor

        UITextField.appearance().textColor = UIColor(AppTheme.textPrimary)
        UITextField.appearance().tintColor = UIColor(AppTheme.primary)
        UITextView.appearance().textColor = UIColor(AppTheme.textPrimary)
        UITextView.appearance().tintColor = UIColor(AppTheme.primary)
        UITextView.appearance().backgroundColor = .clear
        UIStepper.appearance().tintColor = UIColor(AppTheme.textPrimary)
    }
}

/// Owns the accent scheme. Selecting a scheme applies instantly to the token
/// cache and the UIKit proxies — the Appearance page (which observes this
/// store) recolors live so the user sees the pick immediately. The full-tree
/// repaint is committed when the Appearance page is left: `rootEpoch` drives
/// an `.id` on the main `TabView`, so the commit rebuilds every tab with the
/// new accent. Tradeoff: that rebuild resets each tab's navigation stack to
/// its root (the selected tab itself survives — `CoachRouter` lives outside
/// the `.id` boundary).
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var scheme: AccentScheme
    @Published private(set) var rootEpoch = 0

    /// The scheme the tab tree was last (re)built with.
    private var committedScheme: AccentScheme

    init() {
        let stored = AccentScheme.stored()
        scheme = stored
        committedScheme = stored
        AppTheme.setAccentScheme(stored)
    }

    func select(_ newScheme: AccentScheme) {
        guard newScheme != scheme else { return }
        scheme = newScheme
        UserDefaults.standard.set(newScheme.rawValue, forKey: AccentScheme.storageKey)
        AppTheme.setAccentScheme(newScheme)
        AppChrome.apply()
    }

    /// Commits the pending scheme by rebuilding the tab tree, if the applied
    /// scheme differs from the one it was last built with. Deferred a runloop
    /// so it never fights the navigation transition that triggered it.
    func commitIfNeeded() {
        guard committedScheme != scheme else { return }
        committedScheme = scheme
        DispatchQueue.main.async { [weak self] in
            self?.rootEpoch += 1
        }
    }
}

struct AppBackground: View {
    var body: some View {
        AppTheme.backgroundTop
            .ignoresSafeArea()
    }
}

// Flat card one shade lighter than the canvas, separated by a 1px hairline,
// with a 1px inner top highlight just inside it (`AppTheme.cardHighlight`).
// Keeps the `glassCard()` name so call sites don't change — no longer glassy.
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.cardCornerRadius

    func body(content: Content) -> some View {
        content
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .overlay {
                // Inset one point so the highlight sits inside the hairline;
                // the vertical fade keeps it a top edge, not a full ring.
                RoundedRectangle(cornerRadius: cornerRadius - 1, style: .continuous)
                    .inset(by: 1)
                    .stroke(
                        LinearGradient(colors: [AppTheme.cardHighlight, AppTheme.cardHighlight.opacity(0)],
                                       startPoint: .top, endPoint: .center),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
    }
}

/// Glow under the primary pill — see `AppTheme.primaryGlow`. Applied after the
/// capsule clip so the shadow takes the pill's shape.
struct PrimaryGlowModifier: ViewModifier {
    func body(content: Content) -> some View {
        let glow = AppTheme.primaryGlow
        return content.shadow(color: glow.color, radius: glow.radius, x: 0, y: glow.y)
    }
}

/// Glow under a small accent-filled data mark — see `AppTheme.barGlow`.
struct BarGlowModifier: ViewModifier {
    func body(content: Content) -> some View {
        let glow = AppTheme.barGlow
        return content.shadow(color: glow.color, radius: glow.radius, x: 0, y: glow.y)
    }
}

/// Halo around the logger's recording dot — see `AppTheme.recordingGlow`.
struct RecordingGlowModifier: ViewModifier {
    func body(content: Content) -> some View {
        let glow = AppTheme.recordingGlow
        return content.shadow(color: glow.color, radius: glow.radius, x: 0, y: glow.y)
    }
}

/// Faint radial accent glow behind a hero number. Drawn as a circle 1.4× the
/// number's width, squashed to an ellipse so it hugs the figure instead of
/// bleeding into the label above and the caption below. Ends at 0-alpha accent
/// (not `.clear`) so the fade never picks up a gray cast.
struct HeroGlowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geo in
                let diameter = geo.size.width * AppTheme.heroGlowSpread
                RadialGradient(
                    colors: [AppTheme.primary.opacity(AppTheme.heroGlowOpacity), AppTheme.primary.opacity(0)],
                    center: .center, startRadius: 0, endRadius: diameter / 2
                )
                .frame(width: diameter, height: diameter)
                .scaleEffect(x: 1, y: 0.55)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .allowsHitTesting(false)
        }
    }
}

struct SurfaceCardModifier: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.rowCornerRadius
    var border: Color = AppTheme.cardBorder

    func body(content: Content) -> some View {
        content
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
    }
}

extension View {
    /// The card look at the default 22pt radius; pass a smaller radius for
    /// the compact stat tiles (Analytics headline strip: 16pt).
    func glassCard(cornerRadius: CGFloat = AppTheme.cardCornerRadius) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func surfaceCard(cornerRadius: CGFloat = AppTheme.rowCornerRadius, border: Color = AppTheme.cardBorder) -> some View {
        modifier(SurfaceCardModifier(cornerRadius: cornerRadius, border: border))
    }

    /// The primary pill's glow (`AppTheme.primaryGlow`). `PrimaryButtonStyle`
    /// applies it for accent fills; views never call `.shadow(` themselves.
    func primaryGlow() -> some View {
        modifier(PrimaryGlowModifier())
    }

    /// Radial accent glow behind THE hero number of a screen. Phase 1 wears it
    /// in exactly two places: Home's week volume and the Analytics headline
    /// strip.
    func heroGlow() -> some View {
        modifier(HeroGlowModifier())
    }

    /// Glow under a small accent-filled data mark (`AppTheme.barGlow`) — the
    /// week strip's "today" bar on Home. Views never call `.shadow(` themselves.
    func barGlow() -> some View {
        modifier(BarGlowModifier())
    }

    /// Halo around the logger's red recording dot (`AppTheme.recordingGlow`).
    func recordingGlow() -> some View {
        modifier(RecordingGlowModifier())
    }

    func trackerTextEditorStyle() -> some View {
        self
            .foregroundColor(AppTheme.textPrimary)
            .tint(AppTheme.primary)
            .background(Color.clear)
    }

    /// Uppercase tracked micro-label for card headers and stat captions.
    func microLabel(_ color: Color = AppTheme.textTertiary) -> some View {
        self
            .font(.caption2.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

// Full-width pill. The accent fill (the default — THE primary action of a
// screen) renders `AppTheme.primaryGradient` under `.primaryGlow()`; every
// other fill (dark surfaces, `success`) stays flat in the same capsule.
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = AppTheme.primary
    /// Chip sizing — the Workout tab's START on a next-up card: 12pt bold
    /// label, 9pt vertical padding, hugging its content instead of filling
    /// the row. Gradient and glow are unchanged; only the size shrinks.
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isCompact ? .system(size: 12, weight: .bold) : .headline.weight(.bold))
            .foregroundStyle(labelColor)
            .frame(maxWidth: isCompact ? nil : CGFloat.infinity)
            .padding(.vertical, isCompact ? 9 : 16)
            .padding(.horizontal, isCompact ? 16 : 0)
            .background {
                Group {
                    if isAccentFill {
                        AppTheme.primaryGradient
                    } else {
                        fill
                    }
                }
                .opacity(configuration.isPressed ? 0.82 : 1)
            }
            .clipShape(Capsule())
            .overlay {
                if isDarkFill {
                    Capsule()
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }
            }
            .modifier(ConditionalPrimaryGlow(isOn: isAccentFill))
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }

    private var isAccentFill: Bool {
        fill == AppTheme.primary
    }

    // Vivid fills (volt / green / amber) demand a near-black label; dark surface
    // fills keep the light label.
    private var isDarkFill: Bool {
        fill == AppTheme.surfaceElevated || fill == AppTheme.surface ||
        fill == AppTheme.card || fill == AppTheme.fieldBackground
    }

    private var labelColor: Color {
        isDarkFill ? AppTheme.textPrimary : AppTheme.backgroundTop
    }
}

/// Applies `.primaryGlow()` only when `isOn`, so flat fills carry no shadow
/// without branching the whole button body.
private struct ConditionalPrimaryGlow: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.primaryGlow()
        } else {
            content
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.surfaceElevated.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Full-width ghost pill: no fill, hairline capsule, secondary label — the
/// quiet companion beneath a screen's one gradient pill (the logger's Wrap Up).
/// `verticalPadding` 17 matches `PrimaryButtonStyle`'s height for a ghost that
/// sits BESIDE the gradient pill (the coach draft's Revise).
struct GhostButtonStyle: ButtonStyle {
    var verticalPadding: CGFloat = 12
    /// Chip sizing to pair with `PrimaryButtonStyle(isCompact: true)`: the
    /// same 12pt bold label and 9pt vertical padding, content-hugging — the
    /// Workout tab's START on every card that is not up next.
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isCompact ? .system(size: 12, weight: .bold) : .subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: isCompact ? nil : CGFloat.infinity)
            .padding(.vertical, isCompact ? 9 : verticalPadding)
            .padding(.horizontal, isCompact ? 16 : 0)
            .background(AppTheme.mutedFill.opacity(configuration.isPressed ? 1 : 0))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.mutedFill.opacity(configuration.isPressed ? 1 : 0.9))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Drop-in `TextField` replacement whose placeholder renders in
/// `AppTheme.textSecondary`. The system placeholder color is nearly invisible
/// on the app's dark field fills; user-entered text stays `textPrimary` via
/// `TrackerTextFieldStyle` / the UIKit appearance proxies.
struct TrackerTextField: View {
    private let title: String
    private let text: Binding<String>
    private let axis: Axis?

    init(_ title: String, text: Binding<String>, axis: Axis? = nil) {
        self.title = title
        self.text = text
        self.axis = axis
    }

    var body: some View {
        if let axis {
            TextField(title, text: text, prompt: prompt, axis: axis)
        } else {
            TextField(title, text: text, prompt: prompt)
        }
    }

    private var prompt: Text {
        Text(title).foregroundStyle(AppTheme.textSecondary)
    }
}

struct TrackerTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .foregroundStyle(AppTheme.textPrimary)
            .monospacedDigit()
            .tint(AppTheme.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
    }
}

struct TrackerStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let valueText: String

    var body: some View {
        HStack(spacing: 12) {
            stepperButton(systemName: "minus", disabled: value <= range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }

            Text(valueText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
                .frame(minWidth: 72, alignment: .center)

            stepperButton(systemName: "plus", disabled: value >= range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }

    private func stepperButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(disabled ? AppTheme.textTertiary : AppTheme.textPrimary)
                .frame(width: 34, height: 34)
                .background(disabled ? AppTheme.surface : AppTheme.surfaceElevated)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct TagChip: View {
    let title: String
    var color: Color = AppTheme.primary

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.mutedFill)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
    }
}

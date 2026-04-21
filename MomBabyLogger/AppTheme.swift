//
//  AppTheme.swift
//  MomBabyLogger
//
//  Design system tokens — single source of truth for all visual styling.
//  Gender-neutral spa-calm palette designed for moms tracking baby feedings.
//

import SwiftUI

enum AppTheme {

    // MARK: - Raw Palette

    enum Palette {
        static let cream       = SwiftUI.Color(red: 1.000, green: 0.976, blue: 0.957)  // #FFF9F4
        static let cardSurface = SwiftUI.Color(red: 1.000, green: 0.988, blue: 0.976)  // #FFFCF9
        static let deepTeal    = SwiftUI.Color(red: 0.357, green: 0.659, blue: 0.624)  // #5BA89F
        static let lightTeal   = SwiftUI.Color(red: 0.722, green: 0.847, blue: 0.831)  // #B8D8D4
        static let dustySky    = SwiftUI.Color(red: 0.722, green: 0.831, blue: 0.878)  // #B8D4E0
        static let warmSand    = SwiftUI.Color(red: 0.933, green: 0.847, blue: 0.706)  // #EED8B4
        static let sandRose    = SwiftUI.Color(red: 0.910, green: 0.816, blue: 0.769)  // #E8D0C4
        static let caramel     = SwiftUI.Color(red: 0.769, green: 0.627, blue: 0.478)  // #C4A07A
        static let slateBlue   = SwiftUI.Color(red: 0.753, green: 0.769, blue: 0.863)  // #C0C4DC
        static let warmGray    = SwiftUI.Color(red: 0.478, green: 0.455, blue: 0.439)  // #7A7470
        static let darkText    = SwiftUI.Color(red: 0.145, green: 0.133, blue: 0.125)  // #252220
        static let softRed     = SwiftUI.Color(red: 0.784, green: 0.353, blue: 0.353)  // #C85A5A
    }

    // MARK: - Semantic Colors

    enum Colors {
        // Backgrounds
        static let appBackground   = Palette.cream
        static let cardBackground  = Palette.cardSurface
        static let formBackground  = Palette.cream

        // Primary CTA (deep teal — calm, gender-neutral)
        static let primaryAction   = Palette.deepTeal
        static let primaryActionFG = SwiftUI.Color.white

        // Secondary CTA (soft teal fill)
        static let secondaryAction    = Palette.lightTeal
        static let secondaryActionFG  = Palette.deepTeal

        // Destructive (softened red)
        static let destructiveAction  = Palette.softRed

        // Activity type colors
        static let breastFeeding   = Palette.sandRose
        static let bottleFeeding   = Palette.dustySky
        static let formulaFeeding  = Palette.warmSand
        static let wetDiaper       = Palette.dustySky
        static let poopDiaper      = Palette.caramel
        static let mixedDiaper     = Palette.slateBlue

        // Text
        static let primaryText     = Palette.darkText
        static let secondaryText   = Palette.warmGray
        static let tertiaryText    = Palette.warmGray.opacity(0.7)

        // Banner backgrounds
        static let infoBanner      = Palette.dustySky.opacity(0.25)
        static let successBanner   = Palette.lightTeal.opacity(0.35)
        static let warningBanner   = Palette.warmSand.opacity(0.45)

        // Tab bar
        static let tabActive       = Palette.deepTeal
    }

    // MARK: - Typography (SF Pro Rounded throughout)

    enum Typography {
        static let displayLarge  = SwiftUI.Font.system(size: 64, weight: .bold,     design: .rounded)
        static let displayMedium = SwiftUI.Font.system(size: 36, weight: .bold,     design: .rounded)
        static let titleLarge    = SwiftUI.Font.system(.title,   design: .rounded).weight(.bold)
        static let titleMedium   = SwiftUI.Font.system(.title2,  design: .rounded).weight(.semibold)
        static let titleSmall    = SwiftUI.Font.system(.title3,  design: .rounded).weight(.semibold)
        static let sectionHeader = SwiftUI.Font.system(.subheadline, design: .rounded).weight(.semibold)
        static let bodyLarge     = SwiftUI.Font.system(.body,        design: .rounded)
        static let bodyMedium    = SwiftUI.Font.system(.callout,     design: .rounded)
        static let bodySmall     = SwiftUI.Font.system(.subheadline, design: .rounded)
        static let labelMedium   = SwiftUI.Font.system(.footnote,    design: .rounded).weight(.medium)
        static let labelSmall    = SwiftUI.Font.system(.caption,     design: .rounded)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum Radius {
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 12
        static let lg:   CGFloat = 16
        static let xl:   CGFloat = 20
        static let card: CGFloat = 20
        static let pill: CGFloat = 50
    }
}

// MARK: - Shadow Modifiers

struct CardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(
            color: SwiftUI.Color(red: 0.15, green: 0.12, blue: 0.10).opacity(0.09),
            radius: 8, x: 0, y: 3
        )
    }
}

struct InputShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(
            color: SwiftUI.Color(red: 0.15, green: 0.12, blue: 0.10).opacity(0.05),
            radius: 4, x: 0, y: 1
        )
    }
}

// MARK: - View Extensions

extension View {
    func themedCard() -> some View {
        self
            .background(AppTheme.Colors.cardBackground)
            .cornerRadius(AppTheme.Radius.card)
            .modifier(CardShadow())
    }

    func cardShadow() -> some View {
        self.modifier(CardShadow())
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.bodyLarge.weight(.semibold))
            .foregroundColor(AppTheme.Colors.primaryActionFG)
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.md)
            .background(isEnabled ? AppTheme.Colors.primaryAction : AppTheme.Colors.primaryAction.opacity(0.4))
            .cornerRadius(AppTheme.Radius.md)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.bodyLarge.weight(.semibold))
            .foregroundColor(AppTheme.Colors.secondaryActionFG)
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.secondaryAction.opacity(0.4))
            .cornerRadius(AppTheme.Radius.md)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct DiaperCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.bodyLarge.weight(.semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.destructiveAction)
            .cornerRadius(AppTheme.Radius.md)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

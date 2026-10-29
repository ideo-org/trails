//
//  AppFonts.swift
//  Trails
//
//  Typography system defined in docs/stitch/trails/DESIGN.md:
//  1. Curatorial Editorial (Newsreader / Serif): Space titles, exhibition essays, wing names.
//  2. System Interface (Inter / Default): Listings, navigation commands, search fields, general UI.
//  3. Survey & Coordinates (JetBrains Mono / Monospaced): Floor levels, offsets, timestamps, metrics.
//

import SwiftUI

struct AppFonts {

    // MARK: - Curatorial Editorial (Serif)

    /// Display Large: 40pt serif
    static let displayLarge = Font.system(size: 40, weight: .regular, design: .serif)

    /// Display Large Mobile: 32pt serif
    static let displayLargeMobile = Font.system(size: 32, weight: .regular, design: .serif)

    /// Headline Large: 28pt serif
    static let headlineLarge = Font.system(size: 28, weight: .regular, design: .serif)

    /// Headline Medium: 22pt serif
    static let headlineMedium = Font.system(size: 22, weight: .regular, design: .serif)

    // MARK: - System Interface (Sans-Serif / Inter)

    /// Headline Small: 17pt semibold
    static let headlineSmall = Font.system(size: 17, weight: .semibold, design: .default)

    /// Body Large: 16pt regular
    static let bodyLarge = Font.system(size: 16, weight: .regular, design: .default)

    /// Body Medium: 14pt regular
    static let bodyMedium = Font.system(size: 14, weight: .regular, design: .default)

    /// Body Small: 12pt regular
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .default)

    /// Label UI: 13pt medium
    static let labelUI = Font.system(size: 13, weight: .medium, design: .default)

    // MARK: - Survey & Coordinates (Monospaced / JetBrains Mono)

    /// Label Metric: 13pt medium monospaced (metrics, distances, node frequencies)
    static let labelMetric = Font.system(size: 13, weight: .medium, design: .monospaced)

    /// Label Spatial: 11pt medium monospaced (levels, coordinates, timestamps)
    static let labelSpatial = Font.system(size: 11, weight: .medium, design: .monospaced)

    // MARK: - Backward-Compatible Aliases

    static let largeTitle = headlineLarge
    static let title = headlineMedium
    static let title2 = headlineSmall
    static let title3 = headlineSmall
    static let body = bodyMedium
    static let bodyBold = Font.system(size: 14, weight: .semibold, design: .default)
    static let callout = bodyMedium
    static let subheadline = bodySmall
    static let footnote = bodySmall
    static let caption = labelUI
    static let caption2 = labelSpatial
    static let button = labelUI
    static let tabLabel = labelSpatial
    static let badge = labelSpatial

    static func scoreDisplay(size: CGFloat = 48) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
}

// MARK: - Text Style Modifiers

extension View {

    /// Apply curatorial title style (Serif)
    func curatorialTitleStyle() -> some View {
        self
            .font(AppFonts.headlineMedium)
            .foregroundColor(AppColors.deepInk)
    }

    /// Apply heading style
    func headingStyle() -> some View {
        self
            .font(AppFonts.headlineSmall)
            .foregroundColor(AppColors.deepInk)
    }

    /// Apply body style
    func bodyStyle() -> some View {
        self
            .font(AppFonts.bodyMedium)
            .foregroundColor(AppColors.deepInk)
    }

    /// Apply secondary text style
    func secondaryStyle() -> some View {
        self
            .font(AppFonts.bodySmall)
            .foregroundColor(AppColors.onSurfaceVariant)
    }

    /// Apply coordinate/survey metric style (Monospaced)
    func metricStyle() -> some View {
        self
            .font(AppFonts.labelMetric)
            .foregroundColor(AppColors.primary)
    }

    /// Apply caption style
    func captionStyle() -> some View {
        self
            .font(AppFonts.labelSpatial)
            .foregroundColor(AppColors.outline)
    }
}

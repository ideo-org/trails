//
//  AppColors.swift
//  Trails
//
//  Centralized color definitions for Trails branding.
//  Keep the palette aligned with the product's dark, spatial capture aesthetic.
//

import SwiftUI

// MARK: - App Colors

struct AppColors {

    // MARK: - Primary Palette

    /// Trails scanner blue (primary action and spatial markers)
    static let primary = Color(hex: "#2F7BFF")

    /// High-energy cyan used for LiDAR, focus rings, and active surfaces.
    static let secondary = Color(hex: "#67E8F9")

    /// Deep spatial black used behind scanner and library surfaces.
    static let obsidian = Color(hex: "#05070A")

    /// Accent color for highlights
    static let accent = Color(hex: "#B7D7FF")

    /// LiDAR confidence green
    static let lidar = Color(hex: "#45F3A3")

    /// Deep card background
    static let graphite = Color(hex: "#0D121A")

    /// Scan void/dark-fill color
    static let void = Color(hex: "#020304")

    /// Success/positive color
    static let success = Color(hex: "#22C55E")

    /// Warning color
    static let warning = Color(hex: "#F59E0B")

    /// Error/danger color
    static let error = Color(hex: "#EF4444")

    /// Premium/special features
    static let premium = Color(hex: "#A78BFA")

    // MARK: - Streak Colors

    /// Streak flame color (active)
    static let streakActive = Color.orange

    /// Streak flame color (inactive)
    static let streakInactive = Color.gray

    // MARK: - Semantic Colors

    /// Primary background
    static let backgroundPrimary = obsidian

    /// Secondary background (cards, sections)
    static let backgroundSecondary = graphite

    /// Tertiary background
    static let backgroundTertiary = Color(hex: "#172033")

    /// Primary text color
    static let textPrimary = Color.white

    /// Secondary text color
    static let textSecondary = Color.white.opacity(0.74)

    /// Tertiary text color
    static let textTertiary = Color.white.opacity(0.5)

    // MARK: - Tab Bar Colors

    static let tabHome = primary
    static let tabLibrary = accent
    static let tabSettings = secondary

    // MARK: - Dividers and Borders

    static let divider = Color.white.opacity(0.08)
    static let border = Color.white.opacity(0.14)
    static let glass = Color.white.opacity(0.08)
    static let glassStrong = Color.white.opacity(0.14)
    static let controlSurface = Color.white.opacity(0.12)
    static let controlSurfacePressed = Color.white.opacity(0.2)

    static let scannerGradient = LinearGradient(
        colors: [void, obsidian, Color(hex: "#071A2F")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let primaryGradient = LinearGradient(
        colors: [secondary, primary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Color Extensions

extension Color {

    /// Initialize color from hex string
    /// Example: Color(hex: "#FF5733") or Color(hex: "FF5733")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Fallback Colors (for when asset colors aren't configured)

extension AppColors {

    /// Fallback colors using Trails-aligned hex values
    struct Fallback {
        static let primaryGreen = Color(hex: "#45F3A3")
        static let primaryBlue = Color(hex: "#2F7BFF")
        static let accentOrange = Color(hex: "#B7D7FF")
        static let successGreen = Color(hex: "#22C55E")
        static let warningYellow = Color(hex: "#F59E0B")
        static let errorRed = Color(hex: "#EF4444")
        static let premiumPurple = Color(hex: "#8B5CF6")
    }
}

//
//  AppColors.swift
//  Trails
//
//  Centralized color definitions for Trails branding.
//  Preserves the high-performance dark spatial room scanner palette
//  while providing design system tokens from docs/stitch/trails/DESIGN.md.
//

import SwiftUI

// MARK: - App Colors

struct AppColors {

    // MARK: - Trails Palette (PRD v0.1.0 & DESIGN.md)

    /// Primary brand color: Forest Green (structural anchors, primary actions, deep brand presence)
    static let primary = Color(hex: "#173E35")

    /// Secondary accent color: Restrained Brass (spatial waypoints, architectural milestones)
    static let secondary = Color(hex: "#B59A58")

    /// Accent color for highlights
    static let accent = Color(hex: "#B59A58")

    /// Active Journey: Terracotta for the active path
    static let terracotta = Color(hex: "#C66B4E")
    static let activeTrail = terracotta

    /// Spatial Waypoints / Moment Pins: Restrained Brass
    static let mutedBrass = Color(hex: "#B59A58")
    static let momentPin = mutedBrass

    /// Forest Green
    static let forestGreen = Color(hex: "#173E35")
    static let primaryDark = Color(hex: "#002820")

    /// Canvas / Warm Limestone: Base background
    static let canvas = Color(hex: "#F5F1E8")
    static let limestone = Color(hex: "#F5F1E8")

    /// Surfaces
    static let surface = Color(hex: "#FDF9F0")
    static let surfaceDim = Color(hex: "#DDDAD1")
    static let surfaceContainerLowest = Color(hex: "#FFFFFF")
    static let surfaceContainerLow = Color(hex: "#F7F3EA")
    static let surfaceContainer = Color(hex: "#F1EEE5")
    static let surfaceContainerHigh = Color(hex: "#ECE8DF")
    static let surfaceContainerHighest = Color(hex: "#E6E2D9")
    static let elevatedCanvas = Color(hex: "#FAF8F5")
    static let pureWhite = Color(hex: "#FFFFFF")

    /// Dark Ink Text (PRD 10.1)
    static let deepInk = Color(hex: "#202923")
    static let onSurface = Color(hex: "#1C1C16")
    static let onSurfaceVariant = Color(hex: "#414846")
    static let outline = Color(hex: "#717975")
    static let outlineVariant = Color(hex: "#C0C8C4")
    static let onPrimary = Color.white

    // MARK: - Semantic Colors

    static let backgroundPrimary = canvas
    static let backgroundSecondary = surface
    static let backgroundTertiary = surfaceContainer
    static let textPrimary = deepInk
    static let textSecondary = onSurfaceVariant
    static let textTertiary = outline

    static let divider = outlineVariant.opacity(0.3)
    static let border = outlineVariant.opacity(0.4)
    static let glass = Color.white.opacity(0.85)
    static let glassStrong = Color.white.opacity(0.95)
    static let controlSurface = surfaceContainerLow
    static let controlSurfacePressed = surfaceContainerHigh

    /// Volumetric and spatial traces
    static let volumetricTrace = Color(hex: "#173E35").opacity(0.18)
    static let inactiveVector = Color(hex: "#9C9A8E").opacity(0.40)

    /// Success / Positive
    static let success = Color(hex: "#2E7D32")

    /// Warning
    static let warning = Color(hex: "#D97706")

    /// Error / Danger
    static let error = Color(hex: "#BA1A1A")

    /// Premium / Special
    static let premium = mutedBrass

    // MARK: - Viewfinder / Camera Surface Overlays

    /// LiDAR confidence green
    static let lidar = Color(hex: "#45F3A3")

    /// Deep spatial black used behind live camera / scanner HUD
    static let obsidian = Color(hex: "#05070A")

    /// Deep card background
    static let graphite = Color(hex: "#0D121A")

    /// Scan void/dark-fill color
    static let void = Color(hex: "#020304")

    /// Primary Gradient (Forest Green)
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "#1F4E43"), Color(hex: "#173E35")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle Warm Scanner Gradient
    static let scannerGradient = LinearGradient(
        colors: [canvas, surfaceContainerLow],
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

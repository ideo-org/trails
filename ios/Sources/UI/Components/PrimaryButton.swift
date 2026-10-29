//
//  PrimaryButton.swift
//  MyApp
//
//  Primary and secondary button styles for the app.
//

import SwiftUI

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.button)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isEnabled ? AnyShapeStyle(AppColors.primaryGradient) : AnyShapeStyle(Color.gray.opacity(0.55)))
            )
            .shadow(color: isEnabled ? AppColors.primary.opacity(0.28) : .clear, radius: 18, y: 8)
            .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.button)
            .foregroundColor(AppColors.primary)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColors.controlSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppColors.secondary.opacity(0.45), lineWidth: 1)
                    }
            )
            .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Tertiary Button Style (Text-only)

struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.button)
            .foregroundColor(AppColors.accent)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Convenience Extensions

extension Button {

    /// Apply primary button styling
    func primaryStyle(isEnabled: Bool = true) -> some View {
        self.buttonStyle(PrimaryButtonStyle(isEnabled: isEnabled))
    }

    /// Apply secondary button styling
    func secondaryStyle() -> some View {
        self.buttonStyle(SecondaryButtonStyle())
    }

    /// Apply tertiary button styling
    func tertiaryStyle() -> some View {
        self.buttonStyle(TertiaryButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        Button("Primary Button") {}
            .primaryStyle()

        Button("Secondary Button") {}
            .secondaryStyle()

        Button("Tertiary Button") {}
            .tertiaryStyle()

        Button("Disabled Button") {}
            .primaryStyle(isEnabled: false)
            .disabled(true)
    }
    .padding()
}

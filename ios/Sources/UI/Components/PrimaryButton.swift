//
//  PrimaryButton.swift
//  Trails
//
//  Primary and secondary button styles matching the Trails design monograph.
//

import SwiftUI

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.headlineSmall)
            .foregroundColor(AppColors.onPrimary)
            .padding(.horizontal, 24)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(isEnabled ? AnyShapeStyle(AppColors.forestGreen) : AnyShapeStyle(AppColors.outlineVariant.opacity(0.6)))
            )
            .shadow(color: isEnabled ? AppColors.forestGreen.opacity(0.18) : .clear, radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.headlineSmall)
            .foregroundColor(AppColors.forestGreen)
            .padding(.horizontal, 24)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(AppColors.elevatedCanvas)
                    .overlay {
                        Capsule()
                            .stroke(AppColors.forestGreen.opacity(0.14), lineWidth: 1)
                    }
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Tertiary Button Style (Text-only)

struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.labelUI)
            .foregroundColor(AppColors.deepInk)
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

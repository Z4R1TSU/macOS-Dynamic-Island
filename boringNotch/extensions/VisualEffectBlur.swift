//
//  VisualEffectBlur.swift
//  boringNotch
//
//  NSVisualEffectView wrapper and Liquid Glass styling helpers.
//

import SwiftUI

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Liquid Glass Text & Icon Styling

extension View {
    /// Primary text on glass: white with strong drop shadow for readability.
    func glassText() -> some View {
        self
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 1.5, y: 0.5)
    }

    /// Secondary/dimmed text on glass: lighter opacity with shadow.
    func glassSecondaryText() -> some View {
        self
            .foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
    }

    /// Icon styling on glass: white with strong shadow.
    func glassIcon() -> some View {
        self
            .foregroundStyle(.white.opacity(0.95))
            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 0.5)
    }

    /// Surface/card background for glass mode.
    func glassSurface(cornerRadius: CGFloat = 10) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.white.opacity(0.12))
                .shadow(color: .white.opacity(0.05), radius: 0.5, y: -0.5)
        )
    }

    /// Conditionally apply glass or solid styling.
    @ViewBuilder
    func adaptiveText(isGlass: Bool) -> some View {
        if isGlass {
            self.glassText()
        } else {
            self.foregroundStyle(.white)
        }
    }

    /// Subtle linear gradient for closed-notch numeric displays (price tickers, timers).
    /// Provides a left-to-right highlight sweep that feels premium without being distracting.
    func shimmerGradientForeground() -> some View {
        self.foregroundStyle(
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.55), location: 0),
                    .init(color: .white, location: 0.45),
                    .init(color: .white, location: 0.55),
                    .init(color: .white.opacity(0.55), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

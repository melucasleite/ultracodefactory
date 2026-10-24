import SwiftUI

// One place for the app's glass language. On macOS 26+ everything is real
// Liquid Glass; on macOS 15 it falls back to vibrant materials with a
// hairline rim so the layout and hierarchy stay the same.

extension View {
    /// A floating glass surface.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(GlassStyle.make(tint: tint, interactive: interactive), in: .rect(cornerRadius: cornerRadius))
        } else {
            background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).fill((tint ?? .clear).opacity(0.12)))
            }
            .overlay(GlassRim(cornerRadius: cornerRadius))
        }
    }

    /// A glass capsule, for chips and pills.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(GlassStyle.make(tint: tint, interactive: interactive), in: .capsule)
        } else {
            background(Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill((tint ?? .clear).opacity(0.15))))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        }
    }

    /// Lets neighbouring glass shapes blend and morph into each other.
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 12) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// A glass button; `prominent` fills it with the tint.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

@available(macOS 26, *)
private enum GlassStyle {
    static func make(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.35)) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// The light-catching edge of a pane of glass (pre-macOS 26 fallback).
private struct GlassRim: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(
                LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05), .white.opacity(0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.75
            )
    }
}

/// A slow-drifting aurora behind everything: graphite with safety-orange and
/// steel-blue glows. Glass needs something worth refracting.
struct FactoryBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var animated = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { context in
            let t = animated ? context.date.timeIntervalSinceReferenceDate : 0
            MeshGradient(
                width: 3, height: 3,
                points: points(t),
                colors: colors
            )
        }
        .overlay { BlueprintGrid().opacity(scheme == .dark ? 1 : 0.6) }
        .ignoresSafeArea()
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        func wobble(_ base: Float, _ speed: Double, _ phase: Double) -> Float {
            base + Float(sin(t * speed + phase)) * 0.14
        }
        return [
            [0, 0], [wobble(0.5, 0.21, 0), 0], [1, 0],
            [0, wobble(0.5, 0.17, 1)], [wobble(0.5, 0.13, 2), wobble(0.5, 0.19, 3)], [1, wobble(0.5, 0.23, 4)],
            [0, 1], [wobble(0.5, 0.11, 5), 1], [1, 1],
        ]
    }

    private var colors: [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.06, green: 0.07, blue: 0.10), Color(red: 0.13, green: 0.10, blue: 0.24), Color(red: 0.04, green: 0.20, blue: 0.40),
                Color(red: 0.42, green: 0.16, blue: 0.02), Color(red: 0.08, green: 0.08, blue: 0.12), Color(red: 0.05, green: 0.24, blue: 0.38),
                Color(red: 0.70, green: 0.27, blue: 0.00), Color(red: 0.28, green: 0.09, blue: 0.16), Color(red: 0.07, green: 0.08, blue: 0.14),
            ]
        }
        return [
            Color(red: 0.96, green: 0.96, blue: 0.98), Color(red: 0.88, green: 0.88, blue: 1.00), Color(red: 0.76, green: 0.88, blue: 1.00),
            Color(red: 1.00, green: 0.84, blue: 0.68), Color(red: 0.96, green: 0.96, blue: 0.97), Color(red: 0.80, green: 0.92, blue: 1.00),
            Color(red: 1.00, green: 0.72, blue: 0.48), Color(red: 1.00, green: 0.86, blue: 0.88), Color(red: 0.93, green: 0.94, blue: 0.97),
        ]
    }
}

/// A faint blueprint grid.
struct BlueprintGrid: View {
    var step: CGFloat = 28

    var body: some View {
        Canvas { gc, size in
            var path = Path()
            var x: CGFloat = 0
            while x < size.width { path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y < size.height { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)); y += step }
            gc.stroke(path, with: .color(.primary.opacity(0.04)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

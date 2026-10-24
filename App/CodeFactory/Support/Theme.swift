import CodeFactoryKit
import SwiftUI

/// Industrial palette: graphite surfaces, safety-orange accents, and one
/// signal colour per station on the line.
enum Theme {
    static let safetyOrange = Color(red: 1.0, green: 0.52, blue: 0.0)
    static let hazardYellow = Color(red: 1.0, green: 0.78, blue: 0.0)

    static func color(for status: CardStatus) -> Color {
        switch status {
        case .proposed: Color(red: 0.36, green: 0.78, blue: 0.86)
        case .todo: Color(red: 0.35, green: 0.56, blue: 1.0)
        case .pickedUp: safetyOrange
        case .waiting: hazardYellow
        case .done: Color(red: 0.30, green: 0.80, blue: 0.45)
        case .wontDo: Color.gray
        }
    }

    static func color(forKind kind: String) -> Color {
        switch kind.lowercased() {
        case "feature": .blue
        case "bug": .red
        case "chore": .gray
        case "refactor": .purple
        case "spike": .orange
        case "docs": .green
        default: .teal
        }
    }

    static func color(for state: Job.State) -> Color {
        switch state {
        case .running: safetyOrange
        case .waiting: hazardYellow
        case .completed: .green
        case .failed: .red
        case .stopped: .gray
        }
    }

    static func symbol(for state: Job.State) -> String {
        switch state {
        case .running: "gearshape.2.fill"
        case .waiting: "exclamationmark.bubble.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .stopped: "stop.circle.fill"
        }
    }
}

/// Diagonal caution stripes that crawl along, for things under construction.
struct HazardStripes: View {
    var color: Color = Theme.hazardYellow
    var animated = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated)) { context in
            Canvas { gc, size in
                let width: CGFloat = 14
                let phase = animated
                    ? CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)) * width * 2
                    : 0
                var x = -size.height - width * 2 + phase
                while x < size.width + size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + width, y: size.height))
                    path.addLine(to: CGPoint(x: x + width + size.height, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    path.closeSubpath()
                    gc.fill(path, with: .color(color))
                    x += width * 2
                }
            }
        }
    }
}

/// A small pulsing status light.
struct StatusLight: View {
    var color: Color
    var pulsing: Bool

    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.8), radius: on ? 4 : 1)
            .opacity(pulsing && on ? 0.55 : 1)
            .animation(pulsing ? .easeInOut(duration: 0.8).repeatForever() : .default, value: on)
            .onAppear { on = pulsing }
            .onChange(of: pulsing) { _, now in on = now }
    }
}

extension Job {
    var elapsed: String {
        let end = finishedAt ?? .now
        let seconds = max(0, end.timeIntervalSince(startedAt))
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds < 3600 ? [.minute, .second] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? ""
    }

    var actionTitle: String {
        LaunchAction(rawValue: action)?.title ?? action.capitalized
    }

    var actionSymbol: String {
        LaunchAction(rawValue: action)?.symbol ?? "gearshape"
    }
}

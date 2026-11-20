import SwiftUI

/// The black island shape. The top corners flare outward (like the real notch's ears) so a
/// grown island looks poured out of the notch; the bottom corners are round.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = max(0, min(topRadius, rect.width / 2))
        let b = max(0, min(bottomRadius, min(rect.height, rect.width / 2 - t)))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

extension Color {
    /// "#RRGGBB" to a colour, or nil.
    init?(hex: String?) {
        guard let text = hex, text.count == 7, text.hasPrefix("#"),
              let value = UInt32(text.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
    }
}

struct IslandView: View {
    @ObservedObject var controller: IslandController

    var body: some View {
        let geo = controller.geo
        let message = controller.current
        let width: CGFloat = message == nil ? geo.restWidth : controller.expandedWidth
        let height: CGFloat = message.map { controller.expandedHeight(for: $0) } ?? geo.restHeight
        // Real notch: straight sides, small round bottom corners. Fake lip (no notch): the same,
        // plus tiny curves where it meets the top edge, so it looks like it belongs to the screen.
        let top: CGFloat = message == nil ? (geo.hasNotch ? 0 : 4) : 7
        let bottom: CGFloat = message == nil ? (geo.hasNotch ? 9 : 7) : 24

        ZStack(alignment: .top) {
            NotchShape(topRadius: top, bottomRadius: bottom)
                .fill(Color.black)
                .frame(width: width, height: height)

            if let m = message {
                CardView(message: m, controller: controller)
                    .frame(width: width, height: height, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                    .id(m.source + "/" + m.id)
            }
        }
        .frame(width: controller.windowWidth, height: controller.windowHeight, alignment: .top)
    }
}

struct CardView: View {
    let message: IslandMessage
    let controller: IslandController

    private var accent: Color { Color(hex: message.category) ?? Color(red: 0.31, green: 0.55, blue: 1.0) }

    private var symbol: String {
        switch message.kind {
        case "timer": return "timer"
        case "progress": return "arrow.down.circle.fill"
        case "media": return "music.note"
        case "reply": return "bubble.left.fill"
        default: return "bell.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(accent.opacity(0.25))
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(accent)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(message.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let body = message.body {
                        Text(body)
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)

                if let ends = message.endsAt {
                    let now = Date()
                    Text(timerInterval: now...max(ends, now), countsDown: true)
                        .font(.system(size: 14, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(accent)
                }
            }
            .frame(height: 44 - 8)

            if let p = message.progress {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    GeometryReader { geo in
                        Capsule().fill(accent).frame(width: geo.size.width * CGFloat(p))
                    }
                }
                .frame(height: 4)
            }

            if !message.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(message.actions.enumerated()), id: \.offset) { _, action in
                        Button {
                            controller.perform(action, on: message)
                        } label: {
                            Text(action.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.white.opacity(0.16)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, controller.geo.hasNotch ? controller.geo.topInset + 8 : 14)
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { controller.dismiss(message) }
    }
}

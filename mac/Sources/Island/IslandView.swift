import SwiftUI

/// The black island shape. The top corners flare outward (like the real notch's ears) so a
/// grown island looks poured out of the notch; the bottom corners are round. Both radii are
/// animatable, so the corners morph smoothly between the sizes.
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

enum MessageStyle {
    static let defaultAccent = Color(red: 0.31, green: 0.55, blue: 1.0)

    static func symbol(for kind: String) -> String {
        switch kind {
        case "timer": return "timer"
        case "progress": return "arrow.down.circle.fill"
        case "media": return "music.note"
        case "reply": return "bubble.left.fill"
        default: return "bell.fill"
        }
    }
}

struct IslandView: View {
    @ObservedObject var controller: IslandController

    var body: some View {
        let message = controller.shown
        let size = controller.size
        let d = controller.dims(for: size, message: message)

        ZStack(alignment: .top) {
            NotchShape(topRadius: d.top, bottomRadius: d.bottom)
                .fill(Color.black)

            if let m = message {
                CompactLayer(message: m, controller: controller, size: size)
                    .opacity(size == .compact || size == .hover ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: size)
                    .allowsHitTesting(false)

                CardView(message: m, controller: controller)
                    .opacity(size == .expanded ? 1 : 0)
                    .animation(.easeOut(duration: 0.2).delay(size == .expanded ? 0.1 : 0), value: size)
                    .allowsHitTesting(size == .expanded)
            }
        }
        .frame(width: d.width, height: d.height, alignment: .top)
        .clipShape(NotchShape(topRadius: d.top, bottomRadius: d.bottom))
        .contentShape(NotchShape(topRadius: d.top, bottomRadius: d.bottom))
        .onTapGesture { controller.tap() }
        .frame(width: controller.windowBox.width, height: controller.windowBox.height, alignment: .top)
    }
}

/// Compact (and hover): a small icon on the left, short info on the right. On a notch Mac the
/// middle is left empty because that is where the camera is.
struct CompactLayer: View {
    let message: IslandMessage
    let controller: IslandController
    let size: IslandSize

    private var accent: Color { Color(hex: message.category) ?? MessageStyle.defaultAccent }

    @ViewBuilder private var info: some View {
        if let ends = message.endsAt {
            let now = Date()
            Text(timerInterval: now...max(ends, now), countsDown: true)
                .monospacedDigit()
        } else if let p = message.progress {
            Text("\(Int((p * 100).rounded()))%")
        } else {
            Text(message.title)
        }
    }

    var body: some View {
        let c = controller.compactDims
        let gap: CGFloat = controller.geo.hasNotch ? controller.geo.restWidth : 8

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack {
                    Circle().fill(accent.opacity(0.28))
                    Image(systemName: MessageStyle.symbol(for: message.kind))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(accent)
                }
                .frame(width: 22, height: 22)

                Spacer(minLength: gap)

                info
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 16)
            .frame(width: c.width, height: c.height)

            Text(message.body ?? message.title)
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.7))
                .lineLimit(1)
                .padding(.horizontal, 22)
                .frame(width: c.width + 30, height: 20)
                .opacity(size == .hover ? 1 : 0)
                .animation(.easeOut(duration: 0.18), value: size)
        }
        .frame(width: c.width + 30, height: c.height + 20, alignment: .top)
    }
}

/// Expanded: the large rounded card with title, body, progress bar and buttons.
struct CardView: View {
    let message: IslandMessage
    let controller: IslandController

    private var accent: Color { Color(hex: message.category) ?? MessageStyle.defaultAccent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(accent.opacity(0.25))
                    Image(systemName: MessageStyle.symbol(for: message.kind))
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

                if !message.ephemeral {
                    Button {
                        controller.dismiss(message)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 36)

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
        .frame(width: controller.expandedWidth,
               height: controller.expandedHeight(for: message),
               alignment: .top)
    }
}

import SwiftUI
import AppKit

/// The four sizes of the island, like Apple's Dynamic Island.
///  rest     exactly the notch (invisible); on a Mac without a notch a thin lip
///  compact  a little wider: small icon on the left, short info on the right
///  hover    compact grown a little because the mouse is on it (also a tiny grow when idle)
///  expanded a large rounded card: title, body, progress bar, buttons
enum IslandSize {
    case rest, compact, hover, expanded
}

struct IslandDims: Equatable {
    var width: CGFloat
    var height: CGFloat
    var top: CGFloat      // corner curve where it meets the top edge
    var bottom: CGFloat   // rounded bottom corners
}

/// Holds what the island is showing, the waiting messages, the size, and the timers.
/// Message rules are Drop's: high priority goes ahead of everything waiting, low goes last,
/// the same id updates in place, "clear" removes. Nothing runs while idle.
final class IslandController: ObservableObject {
    /// The message that is on now (logical).
    @Published var current: IslandMessage?
    /// The message that is drawn. It stays for a moment after `current` ends so the island can shrink around it.
    @Published var shown: IslandMessage?
    @Published var size: IslandSize = .rest
    @Published var geo: ScreenGeometry = .fallback
    /// Size of the see-through window around the island. It follows the island so it never covers more than it needs.
    @Published var windowBox: CGSize = CGSize(width: 200, height: 30)
    @Published var fullScreen = false

    var sendToConnection: ((String, Int) -> Void)?

    private var queue: [IslandMessage] = []
    private var held: [(message: IslandMessage, date: Date)] = []   // waiting out a full-screen app
    private var dismissTimer: DispatchWorkItem?
    private var pendingDismiss = false
    private var hovering = false
    private var expandedByClick = false
    private var lastMessage: IslandMessage?
    private var shrinkToken = 0
    private var clearToken = 0

    // TEMPORARY test shortcut state (see debugCycle)
    private var forcedSize: IslandSize?
    private var debugIndex = -1

    private static let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.72)
    private static let closeSpring = Animation.spring(response: 0.40, dampingFraction: 0.86)

    // MARK: sizes

    var compactDims: IslandDims {
        if geo.hasNotch {
            return IslandDims(width: geo.restWidth + 128, height: geo.restHeight, top: 6, bottom: 15)
        }
        return IslandDims(width: 200, height: 30, top: 6, bottom: 15)
    }

    var expandedWidth: CGFloat {
        geo.hasNotch ? min(440, max(380, geo.restWidth + 170)) : 380
    }

    func expandedHeight(for m: IslandMessage) -> CGFloat {
        let top: CGFloat = geo.hasNotch ? geo.topInset + 8 : 14
        var height = top + 36 + 14
        if m.progress != nil { height += 16 }
        if !m.actions.isEmpty { height += 40 }
        return max(height, compactDims.height + 40)
    }

    func dims(for s: IslandSize, message m: IslandMessage?) -> IslandDims {
        switch s {
        case .rest:
            return IslandDims(width: geo.restWidth, height: geo.restHeight,
                              top: geo.hasNotch ? 0 : 4, bottom: geo.hasNotch ? 9 : 7)
        case .compact:
            return compactDims
        case .hover:
            if m == nil {
                // Idle hover: just a small grow, so you can see the island is alive.
                return IslandDims(width: geo.restWidth + 12, height: geo.restHeight + 6,
                                  top: geo.hasNotch ? 2 : 5, bottom: 11)
            }
            let c = compactDims
            return IslandDims(width: c.width + 30, height: c.height + 20, top: 8, bottom: 20)
        case .expanded:
            let h = m.map { expandedHeight(for: $0) } ?? 120
            return IslandDims(width: expandedWidth, height: h, top: 12, bottom: 30)
        }
    }

    private func box(for s: IslandSize, message m: IslandMessage?) -> CGSize {
        let idle = (s == .rest) || (s == .hover && m == nil)
        let d = dims(for: s == .compact ? .hover : s, message: m)
        // Extra room so the spring can overshoot without being cut off.
        return idle ? CGSize(width: d.width + 24, height: d.height + 8)
                    : CGSize(width: d.width + 80, height: d.height + 30)
    }

    func setGeometry(_ g: ScreenGeometry) {
        geo = g
        windowBox = box(for: size, message: shown)
    }

    private func desiredSize() -> IslandSize {
        if let forced = forcedSize { return forced }
        guard let m = current else { return hovering ? .hover : .rest }
        if expandedByClick || m.rank == 2 { return .expanded }
        return hovering ? .hover : .compact
    }

    /// Moves to the size that fits the situation, with a spring. The window grows first and shrinks last.
    private func update() {
        let target = desiredSize()
        let newBox = box(for: target, message: shown)
        let growing = newBox.width > windowBox.width + 0.5 || newBox.height > windowBox.height + 0.5
        if growing {
            shrinkToken += 1
            windowBox = newBox
        }
        withAnimation(growing ? IslandController.openSpring : IslandController.closeSpring) {
            size = target
        }
        if !growing && newBox != windowBox {
            shrinkToken += 1
            let token = shrinkToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                guard let self = self, token == self.shrinkToken else { return }
                self.windowBox = self.box(for: self.size, message: self.shown)
            }
        }
    }

    private func setCurrent(_ m: IslandMessage?) {
        current = m
        clearToken += 1
        if let m = m {
            shown = m
        } else {
            let token = clearToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self = self, token == self.clearToken, self.current == nil else { return }
                self.shown = nil
            }
        }
    }

    // MARK: mouse

    func setHover(_ on: Bool) {
        guard on != hovering else { return }
        hovering = on
        if forcedSize != nil { return }
        if !on {
            expandedByClick = false
            if let cur = current, cur.ephemeral {
                finish()
                return
            }
            if pendingDismiss {
                pendingDismiss = false
                scheduleDismiss(after: 1.0)
            }
        }
        update()
    }

    func tap() {
        if forcedSize != nil { return }
        if let cur = current {
            if cur.ephemeral {
                finish()
            } else if expandedByClick && cur.rank < 2 {
                expandedByClick = false     // click again: back to the small size
                update()
            } else {
                expandedByClick = true
                update()
            }
        } else {
            // Idle click: open the last message again (or a short "nothing new" card).
            expandedByClick = true
            setCurrent(idleMessage())
            update()
        }
    }

    private func idleMessage() -> IslandMessage {
        if var last = lastMessage {
            last.ephemeral = true
            last.duration = nil
            last.replyConnection = nil
            return last
        }
        return IslandMessage(id: "island-idle", source: "system", kind: "alert", title: "Island",
                             body: "Nothing new right now", progress: nil, category: nil, priority: "normal",
                             duration: nil, actions: [], quiet: false, endsAt: nil, replyConnection: nil,
                             ephemeral: true)
    }

    // MARK: full screen (true full screen only, not a maximized window)

    func setFullScreen(_ on: Bool) {
        guard on != fullScreen else { return }
        fullScreen = on
        if on {
            // Everything that is not urgent waits outside until the full-screen app is left.
            let now = Date()
            for m in queue where m.rank < 2 { held.append((message: m, date: now)) }
            queue.removeAll { $0.rank < 2 }
            if let cur = current, cur.rank < 2 {
                if !cur.ephemeral { held.append((message: cur, date: now)) }
                finish()
            }
        } else {
            let now = Date()
            let fresh = held.filter { now.timeIntervalSince($0.date) < 120 || $0.message.duration == nil }
            held.removeAll()
            for item in fresh { enqueue(item.message) }
        }
    }

    // MARK: incoming

    func submit(_ line: String, from connection: Int?) {
        switch MessageParser.parse(line) {
        case .rejected(let reason):
            Log.write("Message ignored: \(reason)")
        case .clear(let id, let source):
            Log.write("Clear \(source)/\(id)")
            queue.removeAll { $0.id == id && $0.source == source }
            held.removeAll { $0.message.id == id && $0.message.source == source }
            if let cur = current, cur.id == id, cur.source == source { finish() }
        case .show(var message):
            if message.quiet {
                Log.write("Quiet message \(message.source)/\(message.id) kept out of sight (Mac has no Home card yet)")
                return
            }
            message.replyConnection = connection
            Log.write("Message \(message.source)/\(message.id) kind=\(message.kind) priority=\(message.priority) fullScreen=\(fullScreen)")
            if fullScreen && message.rank < 2 {
                held.removeAll { $0.message.id == message.id && $0.message.source == message.source }
                held.append((message: message, date: Date()))
                return
            }
            enqueue(message)
        }
    }

    private func enqueue(_ message: IslandMessage) {
        // A card you opened by clicking while idle gives way to a real message.
        if let cur = current, cur.ephemeral {
            present(message)
            return
        }
        // Same id from the same source: update in place.
        if let cur = current, cur.id == message.id, cur.source == message.source {
            withAnimation(.easeOut(duration: 0.25)) { setCurrent(message) }
            update()
            if !(hovering || expandedByClick) { schedule(for: message) }
            return
        }
        if let index = queue.firstIndex(where: { $0.id == message.id && $0.source == message.source }) {
            queue[index] = message
            return
        }

        guard let cur = current else {
            present(message)
            return
        }

        switch message.rank {
        case 2:
            if cur.rank < 2 && cur.duration != nil {
                // Urgent: show straight away; the one it pushed aside waits at the front.
                queue.insert(cur, at: 0)
                present(message)
            } else {
                let at = queue.firstIndex(where: { $0.rank < 2 }) ?? queue.count
                queue.insert(message, at: at)
            }
        case 0:
            queue.append(message)
        default:
            let at = queue.firstIndex(where: { $0.rank == 0 }) ?? queue.count
            queue.insert(message, at: at)
        }
    }

    // MARK: showing and finishing

    private func present(_ message: IslandMessage) {
        expandedByClick = false
        pendingDismiss = false
        setCurrent(message)
        schedule(for: message)
        update()
    }

    private func schedule(for message: IslandMessage) {
        var delay: TimeInterval? = message.duration
        if let ends = message.endsAt {
            // A countdown stays until a minute after the moment it counts to.
            delay = max(ends.timeIntervalSinceNow + 60, 5)
        }
        dismissTimer?.cancel()
        dismissTimer = nil
        guard let seconds = delay else { return }   // until cleared
        scheduleDismiss(after: seconds)
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        guard let cur = current else { return }
        let id = cur.id
        let source = cur.source
        dismissTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, let now = self.current, now.id == id, now.source == source else { return }
            if self.hovering || self.expandedByClick {
                self.pendingDismiss = true      // wait until the mouse has left
            } else {
                self.finish()
            }
        }
        dismissTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func finish() {
        dismissTimer?.cancel()
        dismissTimer = nil
        pendingDismiss = false
        expandedByClick = false
        if let cur = current, !cur.ephemeral { lastMessage = cur }
        if !queue.isEmpty {
            present(queue.removeFirst())
        } else {
            setCurrent(nil)
            update()
        }
    }

    func dismiss(_ message: IslandMessage) {
        if let cur = current, cur.id == message.id, cur.source == message.source { finish() }
    }

    // MARK: button replies

    func perform(_ action: IslandAction, on message: IslandMessage) {
        let reply: [String: Any] = [
            "version": 1, "type": "action", "messageId": message.id, "actionId": action.id
        ]
        if let data = try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) {
            // Always saved, so a program that is not still connected can read it later.
            let folder = Listener.directory.appendingPathComponent("replies", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            Log.append(line + "\n", to: folder.appendingPathComponent("\(message.source).jsonl"))
            if let connection = message.replyConnection { sendToConnection?(line + "\n", connection) }
            Log.write("Button \(action.id) pressed on \(message.source)/\(message.id)")
        }
        dismiss(message)
    }

    // MARK: TEMPORARY test shortcut (remove when the sizes are approved)

    /// Each press steps to the next size: Resting, Compact, Hover, Expanded, then back to normal.
    func debugCycle() -> String {
        debugIndex += 1
        dismissTimer?.cancel()
        dismissTimer = nil
        pendingDismiss = false
        expandedByClick = false
        let label: String
        switch debugIndex {
        case 0:
            forcedSize = .rest
            setCurrent(nil)
            label = "Resting"
        case 1:
            forcedSize = .compact
            setCurrent(demoMessage())
            label = "Compact"
        case 2:
            forcedSize = .hover
            label = "Hover"
        case 3:
            forcedSize = .expanded
            label = "Expanded"
        default:
            debugIndex = -1
            forcedSize = nil
            setCurrent(nil)
            label = "Back to normal"
        }
        update()
        Log.write("Test shortcut: \(label)")
        return label
    }

    private func demoMessage() -> IslandMessage {
        return IslandMessage(id: "size-test", source: "test", kind: "progress", title: "Downloading update",
                             body: "Size test, 65 percent done", progress: 0.65, category: "#4F8CFF",
                             priority: "normal", duration: nil,
                             actions: [IslandAction(id: "pause", label: "Pause"), IslandAction(id: "open", label: "Open")],
                             quiet: false, endsAt: nil, replyConnection: nil)
    }
}

import SwiftUI
import AppKit

/// Holds what the island is showing, the waiting messages, and the timers.
/// Same rules as Drop: high priority goes ahead of everything waiting, low goes last,
/// the same id updates in place, "clear" removes, nothing runs while idle.
final class IslandController: ObservableObject {
    @Published var current: IslandMessage?
    @Published var geo: ScreenGeometry = .fallback

    /// The see-through window is bigger than the island so the island can grow inside it.
    let windowWidth: CGFloat = 460
    let windowHeight: CGFloat = 240

    var sendToConnection: ((String, Int) -> Void)?

    private var queue: [IslandMessage] = []
    private var dismissTimer: DispatchWorkItem?
    private static let spring = Animation.spring(response: 0.5, dampingFraction: 0.74)

    // MARK: sizes

    var expandedWidth: CGFloat {
        geo.hasNotch ? min(440, max(380, geo.restWidth + 170)) : 380
    }

    func expandedHeight(for m: IslandMessage) -> CGFloat {
        let top: CGFloat = geo.hasNotch ? geo.topInset + 8 : 14
        var height = top + 44 + 14
        if m.progress != nil { height += 16 }
        if !m.actions.isEmpty { height += 40 }
        return height
    }

    // MARK: incoming

    func submit(_ line: String, from connection: Int?) {
        switch MessageParser.parse(line) {
        case .rejected(let reason):
            Log.write("Message ignored: \(reason)")
        case .clear(let id, let source):
            Log.write("Clear \(source)/\(id)")
            queue.removeAll { $0.id == id && $0.source == source }
            if let cur = current, cur.id == id, cur.source == source { finish() }
        case .show(var message):
            if message.quiet {
                Log.write("Quiet message \(message.source)/\(message.id) kept out of sight (Mac has no Home card yet)")
                return
            }
            message.replyConnection = connection
            Log.write("Message \(message.source)/\(message.id) kind=\(message.kind) priority=\(message.priority)")
            enqueue(message)
        }
    }

    private func enqueue(_ message: IslandMessage) {
        // Same id from the same source: update in place.
        if let cur = current, cur.id == message.id, cur.source == message.source {
            withAnimation(.easeOut(duration: 0.25)) { current = message }
            schedule(for: message)
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
                // Urgent: show straight away, and the one it pushed aside waits at the front.
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
        withAnimation(IslandController.spring) { current = message }
        schedule(for: message)
    }

    private func schedule(for message: IslandMessage) {
        dismissTimer?.cancel()
        dismissTimer = nil

        var delay: TimeInterval? = message.duration
        if let ends = message.endsAt {
            // A countdown stays until a minute after the moment it counts to.
            delay = max(ends.timeIntervalSinceNow + 60, 5)
        }
        guard let seconds = delay else { return }   // until cleared

        let id = message.id
        let source = message.source
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, let cur = self.current, cur.id == id, cur.source == source else { return }
            self.finish()
        }
        dismissTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func finish() {
        dismissTimer?.cancel()
        dismissTimer = nil
        if !queue.isEmpty {
            present(queue.removeFirst())
        } else {
            withAnimation(IslandController.spring) { current = nil }
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
}

import Foundation

// The message format is shared/MESSAGES.md (version 1). This file reads it the way
// Drop (Windows) does: same fields, same limits, same rules for bad messages.

struct IslandAction {
    let id: String
    let label: String
}

struct IslandMessage {
    var id: String
    var source: String
    var kind: String
    var title: String
    var body: String?
    var progress: Double?
    var category: String?
    var priority: String
    /// Seconds to show it; nil means "until_cleared".
    var duration: Double?
    var actions: [IslandAction]
    var quiet: Bool
    var endsAt: Date?
    /// Which open connection sent it (so button replies can go back). Not part of the format.
    var replyConnection: Int?
    /// Made by the island itself when you click it while idle (never sent by another app). Closes when the mouse leaves.
    var ephemeral: Bool = false

    var rank: Int {
        switch priority {
        case "high": return 2
        case "low": return 0
        default: return 1
        }
    }
}

enum Incoming {
    case show(IslandMessage)
    case clear(id: String, source: String)
    case rejected(String)
}

enum MessageParser {
    static let kinds: Set<String> = ["alert", "timer", "progress", "media", "reply"]

    static func shorten(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    static func validSource(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 32 else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        return s.allSatisfy { allowed.contains($0) }
    }

    static func parse(_ line: String) -> Incoming {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return .rejected("not valid JSON") }

        guard let version = (obj["version"] as? NSNumber)?.intValue else { return .rejected("missing version") }
        if version > 1 { return .rejected("newer version \(version) than this island knows") }
        if version != 1 { return .rejected("unknown version \(version)") }

        guard let id = obj["id"] as? String, !id.isEmpty, id.count <= 128 else { return .rejected("missing or bad id") }
        guard let source = obj["source"] as? String, validSource(source), source != "system" else {
            return .rejected("missing or bad source")
        }

        if (obj["type"] as? String) == "clear" { return .clear(id: id, source: source) }

        guard let kind = obj["kind"] as? String, kinds.contains(kind) else { return .rejected("missing or bad kind") }
        guard let title = obj["title"] as? String, !title.isEmpty else { return .rejected("missing title") }

        var progress: Double? = nil
        if let p = (obj["progress"] as? NSNumber)?.doubleValue { progress = min(1, max(0, p)) }

        var category: String? = nil
        if let c = obj["category"] as? String, c.count == 7, c.hasPrefix("#"),
           UInt32(c.dropFirst(), radix: 16) != nil {
            category = c
        }

        var priority = "normal"
        if let p = obj["priority"] as? String, ["low", "normal", "high"].contains(p) { priority = p }

        var duration: Double? = 5
        if let s = obj["duration"] as? String {
            if s == "until_cleared" { duration = nil }
        } else if let n = (obj["duration"] as? NSNumber)?.doubleValue, n > 0 {
            duration = min(n, 3600)
        }

        var actions: [IslandAction] = []
        if let list = obj["actions"] as? [[String: Any]] {
            for item in list.prefix(2) {
                if let aid = item["id"] as? String, let label = item["label"] as? String, !aid.isEmpty {
                    actions.append(IslandAction(id: aid, label: shorten(label, 20)))
                }
            }
        }

        var endsAt: Date? = nil
        if let ms = (obj["endsAt"] as? NSNumber)?.doubleValue {
            endsAt = Date(timeIntervalSince1970: ms / 1000)
        }

        let body = (obj["body"] as? String).map { shorten($0, 240) }

        return .show(IslandMessage(
            id: id, source: source, kind: kind, title: shorten(title, 80), body: body,
            progress: progress, category: category, priority: priority, duration: duration,
            actions: actions, quiet: (obj["quiet"] as? Bool) == true, endsAt: endsAt,
            replyConnection: nil))
    }
}

import Foundation
import CryptoKit
import IOKit

/// Checks the owner's signed activation code. The app holds only the PUBLIC key, so it can
/// check a code but nobody can make one from this file. Codes are made on the owner's PC with
/// tools/IslandCodes. A code is "ISL1-" + base64url(payload 9 bytes + signature 64 bytes):
/// payload = [version 1][6-byte Mac tag, zeros = any Mac][2-byte expiry day since 2026-01-01, 0 = never].
enum Activation {
    static let publicKeyBase64 = "BNxSVudI0+Remz4G23O/KWDwhXTDK7dfM1YtQi/xNlROUAL2RYviAeUappoYy8HniFlp2ZF3vDflOlc1c2eIS00="
    static let prefix = "ISL1-"
    static let domain = "ISLAND-ACTIVATION-v1"

    enum Result {
        case valid
        case invalid(String)
    }

    // MARK: this Mac's Device ID

    /// 12 letters/digits like "ABCD-EF01-2345", made from the Mac's hardware ID (not the ID itself).
    static var deviceTag: Data {
        var uuid = "unknown"
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        if entry != 0 {
            if let value = IORegistryEntryCreateCFProperty(entry, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String {
                uuid = value
            }
            IOObjectRelease(entry)
        }
        let digest = SHA256.hash(data: Data(("island-device-v1|" + uuid).utf8))
        return Data(digest.prefix(6))
    }

    static var deviceID: String {
        let hex = deviceTag.map { String(format: "%02X", $0) }.joined()
        return "\(hex.prefix(4))-\(hex.dropFirst(4).prefix(4))-\(hex.dropFirst(8).prefix(4))"
    }

    // MARK: checking

    static func check(_ raw: String) -> Result {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix(prefix) else { return .invalid("This does not look like an Island code (it should start with ISL1-).") }

        var body = String(text.dropFirst(prefix.count)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while body.count % 4 != 0 { body += "=" }
        guard let bytes = Data(base64Encoded: body), bytes.count == 73 else {
            return .invalid("The code is the wrong length. Copy the whole code, with nothing missing.")
        }
        let payload = Data(bytes.prefix(9))
        let signature = Data(bytes.suffix(64))

        guard let keyData = Data(base64Encoded: publicKeyBase64),
              let key = try? P256.Signing.PublicKey(x963Representation: keyData),
              let sig = try? P256.Signing.ECDSASignature(rawRepresentation: signature)
        else { return .invalid("Internal error reading the code.") }

        let signed = Data(domain.utf8) + payload
        guard key.isValidSignature(sig, for: signed) else { return .invalid("This code is not valid.") }
        guard payload[payload.startIndex] == 1 else { return .invalid("This code is from a newer Island. Please update.") }

        let tag = payload.subdata(in: (payload.startIndex + 1)..<(payload.startIndex + 7))
        if tag.contains(where: { $0 != 0 }) && tag != deviceTag {
            return .invalid("This code was made for a different Mac. Send the owner your Device ID: \(deviceID)")
        }

        let day = Int(payload[payload.startIndex + 7]) << 8 | Int(payload[payload.startIndex + 8])
        if day != 0 {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            let epoch = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 1_767_225_600)
            if let end = calendar.date(byAdding: .day, value: day, to: epoch), Date() > end.addingTimeInterval(86_400) {
                return .invalid("This code has expired. Ask the owner for a new one.")
            }
        }
        return .valid
    }

    // MARK: the saved code

    private static var storedURL: URL {
        Listener.directory.appendingPathComponent("activation.txt")
    }

    /// True if a saved code is still valid (checked again at every start, so expiry works).
    static var isActivated: Bool {
        guard let saved = try? String(contentsOf: storedURL, encoding: .utf8) else { return false }
        if case .valid = check(saved) { return true }
        return false
    }

    static func save(_ code: String) {
        try? FileManager.default.createDirectory(at: Listener.directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? code.trimmingCharacters(in: .whitespacesAndNewlines).write(to: storedURL, atomically: true, encoding: .utf8)
    }
}

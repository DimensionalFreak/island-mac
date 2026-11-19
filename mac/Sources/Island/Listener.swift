import Foundation
import Darwin

/// Receives messages from other apps on this Mac.
///
/// It listens on a private socket file, ~/Library/Application Support/Island/island.sock
/// (the Mac's version of Drop's named pipe). Only your own Mac account can open it, and the
/// network cannot reach it. A program connects and writes one message per line.
/// Nothing polls: macOS wakes us only when something arrives.
final class Listener {
    static let directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Island", isDirectory: true)
    static var socketPath: String { directory.appendingPathComponent("island.sock").path }

    /// (one complete line, id of the connection it came from)
    var onLine: ((String, Int) -> Void)?

    private final class Connection {
        let id: Int
        let fd: Int32
        var source: DispatchSourceRead?
        var buffer = Data()
        var discarding = false
        init(id: Int, fd: Int32) {
            self.id = id
            self.fd = fd
        }
    }

    private var listenFd: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int: Connection] = [:]
    private var nextId = 1

    func start() {
        try? FileManager.default.createDirectory(at: Listener.directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let path = Listener.socketPath
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Log.write("Listener: could not create the socket (errno \(errno))")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < capacity else {
            Log.write("Listener: socket path too long")
            close(fd)
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePointer in
            tuplePointer.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
                _ = path.withCString { strncpy(dest, $0, capacity - 1) }
            }
        }

        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        guard bound == 0 else {
            Log.write("Listener: bind failed (errno \(errno))")
            close(fd)
            return
        }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else {
            Log.write("Listener: listen failed (errno \(errno))")
            close(fd)
            return
        }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        listenFd = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptAll() }
        source.resume()
        acceptSource = source
        Log.write("Listener: ready at \(path)")
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        for connection in connections.values { connection.source?.cancel() }
        connections.removeAll()
        if listenFd >= 0 {
            close(listenFd)
            listenFd = -1
        }
        unlink(Listener.socketPath)
    }

    /// Writes text back to a program that is still connected (used for button replies).
    func send(_ text: String, to connectionId: Int) {
        guard let connection = connections[connectionId], let data = text.data(using: .utf8) else { return }
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress { _ = write(connection.fd, base, raw.count) }
        }
    }

    private func acceptAll() {
        while true {
            let clientFd = accept(listenFd, nil, nil)
            if clientFd < 0 { break }
            _ = fcntl(clientFd, F_SETFL, O_NONBLOCK)
            var on: Int32 = 1
            setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

            let connection = Connection(id: nextId, fd: clientFd)
            nextId += 1
            let source = DispatchSource.makeReadSource(fileDescriptor: clientFd, queue: .main)
            source.setEventHandler { [weak self] in self?.readFrom(connection) }
            source.setCancelHandler { close(clientFd) }
            connection.source = source
            connections[connection.id] = connection
            source.resume()
        }
    }

    private func readFrom(_ connection: Connection) {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let capacity = bytes.count
        let count = read(connection.fd, &bytes, capacity)
        if count > 0 {
            process(Data(bytes[0..<count]), from: connection)
        } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
            connection.source?.cancel()
            connections[connection.id] = nil
        }
    }

    private func process(_ data: Data, from connection: Connection) {
        connection.buffer.append(data)
        while let newline = connection.buffer.firstIndex(of: 10) {
            let lineData = connection.buffer.subdata(in: connection.buffer.startIndex..<newline)
            connection.buffer.removeSubrange(connection.buffer.startIndex...newline)
            if connection.discarding {
                connection.discarding = false
                continue
            }
            if lineData.count > 16000 {
                Log.write("Listener: ignored a line longer than 16000 characters")
                continue
            }
            if let text = String(data: lineData, encoding: .utf8) {
                let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { onLine?(line, connection.id) }
            }
        }
        if connection.buffer.count > 16000 {
            connection.buffer.removeAll()
            connection.discarding = true
        }
    }
}

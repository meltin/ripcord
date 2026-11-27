import Foundation
import RipcordControl

/// The socket the `ripcord` command talks to: owner-only, in this user's temporary folder, and
/// answering only this user's processes. Each connection is one JSON request line and one
/// response line, handled on its own thread so a pick waiting for a choice holds no one up.
/// A client keeps its end open until the answer comes: closing it, even only for writing, reads
/// as having gone away, and what it asked is cancelled.
final class ControlServer: @unchecked Sendable {
  private let path: String
  private let handle: @Sendable (ControlRequest) async -> ControlResponse
  private var listening: Int32 = -1

  init(
    path: String = Control.socketPath,
    handle: @escaping @Sendable (ControlRequest) async -> ControlResponse
  ) {
    self.path = path
    self.handle = handle
  }

  enum StartError: LocalizedError {
    case inUse, tooLong
    case failed(String)

    var errorDescription: String? {
      switch self {
      case .inUse: "Another Ripcord is already answering the ripcord command."
      case .tooLong: "The ripcord command's socket path is too long."
      case .failed(let step): "Couldn't open the ripcord command's socket (\(step))."
      }
    }
  }

  func start() throws {
    // A command gone before its answer is written mustn't take the app down: the write fails
    // instead. The socket's own SO_NOSIGPIPE didn't stop the signal here.
    signal(SIGPIPE, SIG_IGN)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
      throw StartError.tooLong
    }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      buffer.copyBytes(from: bytes)
      buffer[bytes.count] = 0
    }
    // A socket left by a Ripcord that was killed is taken over; one another Ripcord still
    // answers is left alone.
    if FileManager.default.fileExists(atPath: path) {
      if Self.connects(to: &address) { throw StartError.inUse }
      unlink(path)
    }
    let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard socketFD >= 0 else { throw StartError.failed("socket") }
    // Owner-only from the moment it exists: no gap between creating it and locking it down.
    let mask = umask(0o177)
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    umask(mask)
    guard bound == 0, listen(socketFD, 8) == 0 else {
      close(socketFD)
      throw StartError.failed("bind")
    }
    listening = socketFD
    Thread.detachNewThread { [self] in acceptLoop(socketFD) }
  }

  func stop() {
    guard listening >= 0 else { return }
    close(listening)
    listening = -1
    unlink(path)
  }

  private static func connects(to address: inout sockaddr_un) -> Bool {
    let probe = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(probe) }
    return withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
      }
    }
  }

  private func acceptLoop(_ socketFD: Int32) {
    while true {
      let client = accept(socketFD, nil, nil)
      guard client >= 0 else { return }
      Thread.detachNewThread { [self] in serve(client) }
    }
  }

  private func serve(_ client: Int32) {
    defer { close(client) }
    // Only this user's processes: the socket's mode says so, and the peer is checked too.
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { return }
    // The request is one line; read what's there as it comes, not to the end of the stream,
    // which stays open for the answer.
    var line = Data()
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while !line.contains(UInt8(ascii: "\n")) {
      let count = read(client, &buffer, buffer.count)
      guard count > 0 else { break }
      line.append(contentsOf: buffer.prefix(count))
      // A pick's lines, at most, and some room: anything bigger is turned away.
      if line.count > 16 << 20 { return }
    }
    // Nothing asked, as when another Ripcord checks this one is alive: nothing to answer.
    guard !line.isEmpty else { return }
    let response: ControlResponse
    if let request = try? JSONDecoder().decode(ControlRequest.self, from: line) {
      let answer = Answer()
      let done = DispatchSemaphore(value: 0)
      let task = Task { [handle] in
        answer.response = await handle(request)
        done.signal()
      }
      // A command that goes away (Ctrl-C on a pick) closes its end: the request is cancelled.
      while done.wait(timeout: .now() + 0.25) == .timedOut {
        var peer = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
        if poll(&peer, 1, 0) > 0 {
          task.cancel()
          done.wait()
          return
        }
      }
      response = answer.response ?? ControlResponse(error: "ripcord: no answer.")
    } else {
      response = ControlResponse(error: "ripcord: a request this Ripcord doesn't understand.")
    }
    if let data = try? JSONEncoder().encode(response) {
      let bytes = [UInt8](data) + [UInt8(ascii: "\n")]
      _ = bytes.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
    }
  }

  /// Handed from the task that answers to the thread that waits for it.
  private final class Answer: @unchecked Sendable {
    var response: ControlResponse?
  }
}

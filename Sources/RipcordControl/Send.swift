import Foundation

extension Control {
  /// Asks the running app over its socket and waits for the answer: for a pick, until one is
  /// chosen. Every failure comes back as an error response, so a caller that serves several
  /// requests, as `ripcord mcp` does, carries on.
  public static func send(_ request: ControlRequest) -> ControlResponse {
    let path = socketPath
    let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard socketFD >= 0 else { return ControlResponse(error: "ripcord: couldn't open a socket.") }
    let handle = FileHandle(fileDescriptor: socketFD, closeOnDealloc: true)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
      return ControlResponse(error: "ripcord: the socket path is too long: \(path)")
    }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      buffer.copyBytes(from: pathBytes)
      buffer[pathBytes.count] = 0
    }
    let connected = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard connected == 0 else { return ControlResponse(error: "ripcord: Ripcord isn't running.") }
    do {
      try handle.write(contentsOf: try JSONEncoder().encode(request) + Data("\n".utf8))
    } catch {
      return ControlResponse(error: "ripcord: \(error.localizedDescription)")
    }
    // One line back, once the app has done it; the app closes the connection after it.
    var reply = Data()
    while let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty {
      reply.append(chunk)
      if chunk.contains(UInt8(ascii: "\n")) { break }
    }
    return (try? JSONDecoder().decode(ControlResponse.self, from: reply))
      ?? ControlResponse(error: "ripcord: Ripcord closed the connection without an answer.")
  }
}

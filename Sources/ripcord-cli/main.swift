import Foundation
import RipcordControl

// `ripcord`: talks to the running Ripcord over its socket. Exit codes: 0 done, 1 a pick
// cancelled, 2 an error, 64 a usage error.
func fail(_ message: String, code: Int32) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(code)
}

let request: ControlRequest
switch Control.request(
  from: Array(CommandLine.arguments.dropFirst()),
  stdin: { String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) })
{
case .success(let parsed): request = parsed
case .failure: fail(Control.usage, code: 64)
}

let path = Control.socketPath
let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
guard socketFD >= 0 else { fail("ripcord: couldn't open a socket.", code: 2) }
var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(path.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
  fail("ripcord: the socket path is too long: \(path)", code: 2)
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
guard connected == 0 else { fail("ripcord: Ripcord isn't running.", code: 2) }

let handle = FileHandle(fileDescriptor: socketFD, closeOnDealloc: true)
do {
  handle.write(try JSONEncoder().encode(request) + Data("\n".utf8))
} catch {
  fail("ripcord: \(error.localizedDescription)", code: 2)
}
// One line back, once the app has done it: for a pick, once something is chosen.
var reply = Data()
while let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty {
  reply.append(chunk)
  if chunk.contains(UInt8(ascii: "\n")) { break }
}
guard let response = try? JSONDecoder().decode(ControlResponse.self, from: reply) else {
  fail("ripcord: Ripcord closed the connection without an answer.", code: 2)
}
if let output = response.output { print(output) }
if let error = response.error { FileHandle.standardError.write(Data((error + "\n").utf8)) }
exit(response.exitCode)

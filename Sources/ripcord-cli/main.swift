import Foundation
import RipcordControl

// `ripcord`: talks to the running Ripcord over its socket. Exit codes: 0 done, 1 a pick
// cancelled, 2 an error, 64 a usage error.
func fail(_ message: String, code: Int32) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(code)
}

// An app that closes the connection early is reported, not left to kill the command.
signal(SIGPIPE, SIG_IGN)

if CommandLine.arguments.dropFirst().first == "mcp" {
  guard CommandLine.arguments.count == 2 else { fail(Control.usage, code: 64) }
  serveMCP()
}

let request: ControlRequest
switch Control.request(
  from: Array(CommandLine.arguments.dropFirst()),
  stdin: { String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) })
{
case .success(let parsed): request = parsed
case .failure: fail(Control.usage, code: 64)
}

let response = Control.send(request)
if let output = response.output { print(output) }
if let error = response.error { FileHandle.standardError.write(Data((error + "\n").utf8)) }
exit(response.exitCode)

/// `ripcord mcp`: reads a message a line until stdin ends. A tool call runs on its own thread,
/// so a pick waiting for the user doesn't hold up the next message; each answer is written
/// whole, one line at a time, straight to stdout.
func serveMCP() -> Never {
  let output = NSLock()
  func write(_ data: Data) {
    output.lock()
    defer { output.unlock() }
    try? FileHandle.standardOutput.write(contentsOf: data + Data("\n".utf8))
  }
  while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty else { continue }
    let data = Data(line.utf8)
    // Only a tool call can wait on the app; the rest are answered before the next line is read.
    guard line.contains(#""tools/call""#) else {
      if let answer = MCP.respond(to: data, send: Control.send) { write(answer) }
      continue
    }
    Thread.detachNewThread {
      if let answer = MCP.respond(to: data, send: Control.send) { write(answer) }
    }
  }
  // Leaving drops the sockets of any pick still waiting, which closes its panel.
  exit(0)
}

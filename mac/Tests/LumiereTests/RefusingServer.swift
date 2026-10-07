import Foundation
import Darwin

/// A server that is up and says no: every request answered 403. For the
/// tests of a refusal, which an address nothing listens on can no longer
/// stand in for — that is the server being away, and a change made then is
/// kept and sent later rather than rolled back.
final class RefusingServer: @unchecked Sendable {
    let port: UInt16
    private let socketFD: Int32

    init() {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        self.socketFD = socketFD
        var yes: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        listen(socketFD, 16)
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(socketFD, $0, &length) }
        }
        port = UInt16(bigEndian: bound.sin_port)
        let fd = socketFD
        Thread.detachNewThread {
            let reply = Array("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { return }
                var buffer = [UInt8](repeating: 0, count: 4096)
                _ = read(client, &buffer, buffer.count)
                _ = reply.withUnsafeBufferPointer { write(client, $0.baseAddress, $0.count) }
                close(client)
            }
        }
    }

    var url: URL { URL(string: "http://127.0.0.1:\(port)")! }

    deinit { close(socketFD) }
}

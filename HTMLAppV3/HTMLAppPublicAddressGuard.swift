import Foundation
import Darwin

/// Fail-closed public-address DNS screening for the consent-gated HTTPS bridge.
///
/// DNS preflight is paired with URLSession's actual remote-address metrics to
/// detect DNS rebinding and proxy changes before any data is returned to HTML.
/// URLSession does not expose a socket-level IP pinning API, so private-network
/// apps should not treat this as a substitute for OS network isolation.
enum HTMLAppPublicAddressGuard {
    enum Failure: LocalizedError {
        case dns, privateAddress, connectionMismatch
        var errorDescription: String? {
            switch self {
            case .dns: return "The requested public hostname could not be resolved."
            case .privateAddress: return "Native networking blocked a nonpublic address."
            case .connectionMismatch:
                return "The connection's address could not be verified as the approved public destination."
            }
        }
    }

    static func publicDNSAddresses(for host: String) async throws -> Set<String> {
        try await Task.detached(priority: .utility) {
            try resolve(host)
        }.value
    }

    private static func resolve(_ host: String) throws -> Set<String> {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = Int32(SOCK_STREAM)
        hints.ai_flags = AI_ADDRCONFIG
        var head: UnsafeMutablePointer<addrinfo>?
        let result = host.withCString { getaddrinfo($0, nil, &hints, &head) }
        guard result == 0, let first = head else { throw Failure.dns }
        defer { freeaddrinfo(first) }
        var addresses = Set<String>()
        var next: UnsafeMutablePointer<addrinfo>? = first
        while let node = next {
            let info = node.pointee
            guard let addr = info.ai_addr,
                  let numeric = numericAddress(addr) else {
                throw Failure.privateAddress
            }
            guard isPublicIP(numeric) else { throw Failure.privateAddress }
            addresses.insert(numeric)
            next = info.ai_next
        }
        guard !addresses.isEmpty else { throw Failure.dns }
        return addresses
    }

    private static func numericAddress(_ address: UnsafePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        switch Int32(address.pointee.sa_family) {
        case AF_INET:
            var value = UnsafeRawPointer(address)
                .assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
            let ok = withUnsafePointer(to: &value) {
                inet_ntop(AF_INET, $0, &buffer, socklen_t(buffer.count))
            }
            return ok == nil ? nil : String(cString: buffer)
        case AF_INET6:
            var value = UnsafeRawPointer(address)
                .assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
            let ok = withUnsafePointer(to: &value) {
                inet_ntop(AF_INET6, $0, &buffer, socklen_t(buffer.count))
            }
            return ok == nil ? nil : String(cString: buffer)
        default:
            return nil
        }
    }

    static func isPublicIP(_ ip: String) -> Bool {
        if ip.contains(":") {
            var addr = in6_addr()
            guard ip.withCString({ inet_pton(AF_INET6, $0, &addr) }) == 1 else { return false }
            let octets = withUnsafeBytes(of: &addr) { Array($0) }
            // Restrict to ordinary globally routed IPv6 space 2000::/3.
            // This excludes loopback, ULA, link-local, multicast, NAT64,
            // IPv4-mapped and unspecified addresses.
            guard octets.count == 16, octets[0] >= 0x20,
                  octets[0] <= 0x3f else { return false }
            // IPv6 documentation, Teredo (embedded private IPv4), and 6to4.
            if octets[0] == 0x20 && octets[1] == 0x01 &&
                (octets[2] == 0x0d && octets[3] == 0xb8 ||
                 octets[2] == 0x00 && octets[3] == 0x00) { return false }
            if octets[0] == 0x20 && octets[1] == 0x02 { return false }
            return true
        }

        var addr = in_addr()
        guard ip.withCString({ inet_pton(AF_INET, $0, &addr) }) == 1 else { return false }
        let o = withUnsafeBytes(of: &addr) { Array($0) }
        guard o.count == 4, o[0] > 0, o[0] < 224 else { return false }
        if o[0] == 10 || o[0] == 127 || o[0] == 0 { return false }
        if o[0] == 172 && (16...31).contains(Int(o[1])) { return false }
        if o[0] == 192 && o[1] == 168 { return false }
        if o[0] == 169 && o[1] == 254 { return false }
        if o[0] == 100 && (64...127).contains(Int(o[1])) { return false }
        if o[0] == 192 && o[1] == 0 &&
            (o[2] == 0 || o[2] == 2) { return false }
        if o[0] == 198 && (o[1] == 18 || o[1] == 19 ||
                           o[1] == 51 && o[2] == 100) { return false }
        if o[0] == 203 && o[1] == 0 && o[2] == 113 { return false }
        return true
    }
}

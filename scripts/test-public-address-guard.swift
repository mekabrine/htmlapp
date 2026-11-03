import Foundation

@main
struct HTMLAppPublicAddressGuardTests {
    static func main() {
        let rejected = ["127.0.0.1", "169.254.169.254", "192.168.1.5",
                        "172.31.255.255", "100.64.1.1", "10.0.0.1",
                        "0.0.0.0", "198.18.0.1", "203.0.113.1",
                        "::1", "::ffff:127.0.0.1", "fe80::1",
                        "fc00::1", "2001:db8::1", "2002:c0a8:0101::"]
        for address in rejected {
            precondition(!HTMLAppPublicAddressGuard.isPublicIP(address),
                         "Must block nonpublic IP: \(address)")
        }
        for address in ["8.8.8.8", "1.1.1.1", "2606:4700:4700::1111"] {
            precondition(HTMLAppPublicAddressGuard.isPublicIP(address),
                         "Must allow normal public IP: \(address)")
        }
        print("Public address screening fixtures passed.")
    }
}

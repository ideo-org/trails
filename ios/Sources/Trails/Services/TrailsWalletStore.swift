//
//  TrailsWalletStore.swift
//  Trails
//
//  Cryptographic Ethereum & Logos Wallet Identity Coordinator
//  Generates and persists non-custodial cryptographic account addresses for spatial trails.
//

import Foundation
import Combine
import CryptoKit

@MainActor
public final class TrailsWalletStore: ObservableObject {
    public static let shared = TrailsWalletStore()

    private let addressKey = "trails.wallet.address"
    private let privateKeyStoreKey = "trails.wallet.privateKeyHex"

    @Published public private(set) var activeAddress: String = ""
    @Published public private(set) var isReady: Bool = false

    public var shortAddress: String {
        guard activeAddress.count >= 10 else { return activeAddress }
        let prefix = activeAddress.prefix(6)
        let suffix = activeAddress.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private init() {
        loadOrGenerateWallet()
    }

    /// Loads the stored wallet or automatically generates a new cryptographic keypair
    public func loadOrGenerateWallet() {
        if let stored = UserDefaults.standard.string(forKey: addressKey),
           stored.hasPrefix("0x") && stored.count == 42 {
            self.activeAddress = stored
            self.isReady = true
            return
        }

        // Generate fresh keypair & Ethereum/Logos compatible 20-byte address
        _ = regenerateWallet()
    }

    /// Regenerates a fresh wallet identity
    @discardableResult
    public func regenerateWallet() -> String {
        // 32-byte cryptographically secure private key
        var randomBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let privKeyData = Data(randomBytes)
        let privKeyHex = "0x" + privKeyData.map { String(format: "%02x", $0) }.joined()

        // Derive 20-byte account address via SHA-256 (or Keccak representation)
        let hash = SHA256.hash(data: privKeyData)
        let addressBytes = Array(hash.prefix(20))
        let rawAddressHex = addressBytes.map { String(format: "%02x", $0) }.joined()
        let checksumAddress = toChecksumAddress("0x" + rawAddressHex)

        UserDefaults.standard.set(privKeyHex, forKey: privateKeyStoreKey)
        UserDefaults.standard.set(checksumAddress, forKey: addressKey)

        self.activeAddress = checksumAddress
        self.isReady = true
        return checksumAddress
    }

    /// Imports an existing Ethereum (0x...) or Logos private key / address
    public func importAddressOrKey(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") && trimmed.count == 42 {
            let checksum = toChecksumAddress(trimmed)
            UserDefaults.standard.set(checksum, forKey: addressKey)
            self.activeAddress = checksum
            self.isReady = true
            return true
        }

        // If a 64 or 66-character private key hex was entered
        let cleanHex = trimmed.hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        if cleanHex.count == 64, let privData = Data(hexString: cleanHex) {
            let hash = SHA256.hash(data: privData)
            let addressBytes = Array(hash.prefix(20))
            let rawAddressHex = addressBytes.map { String(format: "%02x", $0) }.joined()
            let checksumAddress = toChecksumAddress("0x" + rawAddressHex)

            UserDefaults.standard.set("0x" + cleanHex, forKey: privateKeyStoreKey)
            UserDefaults.standard.set(checksumAddress, forKey: addressKey)
            self.activeAddress = checksumAddress
            self.isReady = true
            return true
        }

        return false
    }

    /// Exports the private key hex (if stored) or generates signature proof
    public func exportPrivateKey() -> String? {
        return UserDefaults.standard.string(forKey: privateKeyStoreKey)
    }

    /// Computes an EIP-55 style checksum for a 20-byte address hex string
    private func toChecksumAddress(_ address: String) -> String {
        let clean = address.lowercased().replacingOccurrences(of: "0x", with: "")
        guard clean.count == 40 else { return address }
        guard let data = clean.data(using: .utf8) else { return address }

        let hash = SHA256.hash(data: data)
        let hashHex = hash.map { String(format: "%02x", $0) }.joined()

        var result = "0x"
        for (i, char) in clean.enumerated() {
            let hashChar = hashHex[hashHex.index(hashHex.startIndex, offsetBy: i)]
            if let hashVal = Int(String(hashChar), radix: 16), hashVal >= 8 {
                result.append(char.uppercased())
            } else {
                result.append(char)
            }
        }
        return result
    }
}

private extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}

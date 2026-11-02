//
//  TrailsIdentityGenerator.swift
//  Trails
//
//  Decentralized Spatial Identity & ENS-compatible Handle Generator
//  Produces unique, human-readable usernames and ENS domains.
//

import Foundation

public struct TrailsIdentityGenerator {

    private static let adjectives: [String] = [
        "wandering", "spatial", "sol", "terra", "silent", "alpine",
        "coastal", "canyon", "cedar", "lunar", "ember", "zenith",
        "ancient", "echo", "drift", "verdant", "misty", "stone",
        "summit", "aurora", "horizon", "harbor", "breeze", "ridge",
        "forest", "valley", "lichen", "obsidian", "river", "glacier"
    ]

    private static let nouns: [String] = [
        "nomad", "scout", "explorer", "pathfinder", "surveyor",
        "keeper", "pilgrim", "cartographer", "walker", "ranger",
        "voyager", "seeker", "guide", "wayfarer", "strider",
        "roamer", "naturalist", "rambler", "chronicler", "wanderer"
    ]

    /// Generates a random poetic username, e.g. "wandering-cedar-42"
    public static func generateRandomUsername() -> String {
        let adj = adjectives.randomElement() ?? "wandering"
        let noun = nouns.randomElement() ?? "nomad"
        let number = Int.random(in: 10...999)
        return "\(adj)-\(noun)-\(number)"
    }

    /// Formats a username into a pleasant display name, e.g. "wandering-cedar-42" -> "Wandering Cedar 42"
    public static func generateDisplayName(from username: String) -> String {
        let clean = username.replacingOccurrences(of: "@", with: "")
        let parts = clean.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." })
        return parts.map { word -> String in
            if let num = Int(word) {
                return "\(num)"
            }
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    /// Formats an ENS / Logos domain from a username
    public static func formatENS(for username: String) -> String {
        let clean = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        if clean.hasSuffix(".eth") || clean.hasSuffix(".logos") {
            return clean
        }
        return "\(clean).trails.eth"
    }

    /// Validates username format: 3-64 chars, lowercase alphanumeric, hyphens, underscores, or dots
    public static func isValidFormat(_ username: String) -> Bool {
        let clean = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        guard clean.count >= 3 && clean.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_.")
        return clean.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

//
//  TrailsLogosClient.swift
//  Trails
//
//  Client for trails.logos v0.1.0 Decentralized Trail Registry & Storage REST API
//  Connects native iOS app to the local or remote Logos node (default port 8095).
//  PRD v0.4.0 §18 Backend contract implementation.
//

import Foundation
import Combine

public struct LogosPublicationReceipt: Codable, Identifiable, Sendable {
    public var id: String { trailId }
    public let trailId: String
    public let revision: Int
    public let packageCid: String
    public let packageSizeBytes: Int
    public let networkIdentifier: String
    public let registryProgramIdentifier: String
    public let registryRecordReference: String
    public let transactionReference: String
    public let verifiedAt: String
}

public struct LogosCapabilities: Codable, Sendable {
    public let hasPhotos: Bool
    public let hasVideos: Bool
    public let hasVoice: Bool
    public let hasText: Bool
    public let hasGeographicPath: Bool
    public let hasLocalSpatialPath: Bool
    public let hasSpatialGeometry: Bool
    public let hasPlan: Bool
    public let hasAlignmentAssets: Bool

    public init(
        hasPhotos: Bool = false,
        hasVideos: Bool = false,
        hasVoice: Bool = false,
        hasText: Bool = false,
        hasGeographicPath: Bool = false,
        hasLocalSpatialPath: Bool = false,
        hasSpatialGeometry: Bool = false,
        hasPlan: Bool = false,
        hasAlignmentAssets: Bool = false
    ) {
        self.hasPhotos = hasPhotos
        self.hasVideos = hasVideos
        self.hasVoice = hasVoice
        self.hasText = hasText
        self.hasGeographicPath = hasGeographicPath
        self.hasLocalSpatialPath = hasLocalSpatialPath
        self.hasSpatialGeometry = hasSpatialGeometry
        self.hasPlan = hasPlan
        self.hasAlignmentAssets = hasAlignmentAssets
    }
}

public struct LogosTrailPublication: Codable, Identifiable, Sendable {
    public var id: String { trailId }
    public let trailId: String
    public let publisherAccount: String
    public let currentRevision: Int
    public let packageCid: String
    public let packageSizeBytes: Int
    public let packageFormatVersion: String
    public let title: String
    public let shortDescription: String?
    public let recordedAt: String
    public let capabilities: LogosCapabilities
    public let listed: Bool
    public let createdAt: String
    public let updatedAt: String
}

public struct LogosCatalogResponse: Codable, Sendable {
    public let items: [LogosTrailPublication]
    public let nextCursor: String?
}

public struct LogosDiscoveryResponse: Codable, Sendable {
    public let items: [DiscoveryRecord]
    public let nextCursor: String?
}

public struct LogosCreatorsResponse: Codable, Sendable {
    public let items: [CreatorRecord]
}

@MainActor
public final class TrailsLogosClient: ObservableObject {
    public static let shared = TrailsLogosClient()

    @Published public var isConnected: Bool = false
    @Published public var isPublishing: Bool = false
    @Published public var isDownloading: Bool = false
    @Published public var lastReceipt: LogosPublicationReceipt?
    @Published public var networkTrails: [LogosTrailPublication] = []
    @Published public var lastError: String?

    public var baseURL: URL {
        AppConfiguration.logosBaseURL
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Health Check

    @discardableResult
    public func checkHealth() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                self.isConnected = false
                return false
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["status"] as? String == "ok" {
                self.isConnected = true
                return true
            }
            self.isConnected = false
            return false
        } catch {
            self.isConnected = false
            return false
        }
    }

    // MARK: - PRD v0.4.0 Discovery (List Trails & Filtering - §6, §7, §18)

    public func fetchDiscoveryRecords(
        area: DiscoveryAreaFilter? = nil,
        creatorId: String? = nil,
        query: String? = nil,
        limit: Int = 50,
        cursor: String? = nil
    ) async throws -> [DiscoveryRecord] {
        var components = URLComponents(url: baseURL.appendingPathComponent("discovery"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(limit)")]

        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let creatorId, !creatorId.isEmpty {
            queryItems.append(URLQueryItem(name: "creatorId", value: creatorId))
        }
        if let query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: query))
        }
        if let area {
            switch area {
            case .all:
                break
            case .nearMe(let lat, let lon, let radiusKm):
                queryItems.append(URLQueryItem(name: "area", value: "near:\(lat),\(lon),\(radiusKm)"))
            case .boundingBox(let minLat, let minLon, let maxLat, let maxLon):
                queryItems.append(URLQueryItem(name: "area", value: "bbox:\(minLat),\(minLon),\(maxLat),\(maxLon)"))
            case .chosenPlace(let place):
                queryItems.append(URLQueryItem(name: "area", value: "near:\(place.latitude),\(place.longitude),15.0"))
            }
        }

        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Failed to fetch discovery records"
            throw NSError(domain: "TrailsLogosClient", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let decoded = try JSONDecoder().decode(LogosDiscoveryResponse.self, from: data)
        return decoded.items
    }

    public func fetchDiscoveryRecord(trailId: String) async throws -> DiscoveryRecord {
        let url = baseURL.appendingPathComponent("discovery").appendingPathComponent(trailId)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Discovery record not found"
            throw NSError(domain: "TrailsLogosClient", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(DiscoveryRecord.self, from: data)
    }

    public func fetchCreators(query: String? = nil) async throws -> [CreatorRecord] {
        var components = URLComponents(url: baseURL.appendingPathComponent("creators"), resolvingAgainstBaseURL: false)!
        if let query, !query.isEmpty {
            components.queryItems = [URLQueryItem(name: "query", value: query)]
        }
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Failed to fetch creators"
            throw NSError(domain: "TrailsLogosClient", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let decoded = try JSONDecoder().decode(LogosCreatorsResponse.self, from: data)
        return decoded.items
    }

    public func getPublicationStatus(operationId: String) async throws -> LogosPublicationReceipt {
        let url = baseURL.appendingPathComponent("publications").appendingPathComponent(operationId)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Operation not found"
            throw NSError(domain: "TrailsLogosClient", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(LogosPublicationReceipt.self, from: data)
    }

    // MARK: - Legacy Catalog (List Trails)

    public func fetchNetworkTrails(limit: Int = 50, cursor: String? = nil) async throws -> [LogosTrailPublication] {
        var components = URLComponents(url: baseURL.appendingPathComponent("trails"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Failed to fetch trails"
            throw NSError(domain: "TrailsLogosClient", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let decoded = try JSONDecoder().decode(LogosCatalogResponse.self, from: data)
        self.networkTrails = decoded.items
        return decoded.items
    }

    // MARK: - Download Package Archive

    public func downloadTrailArchive(trailId: String, revision: Int? = nil) async throws -> Data {
        self.isDownloading = true
        defer { self.isDownloading = false }

        var url = baseURL.appendingPathComponent("trails").appendingPathComponent(trailId).appendingPathComponent("download")
        if let revision {
            var comp = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comp.queryItems = [URLQueryItem(name: "revision", value: "\(revision)")]
            url = comp.url!
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Failed to download trail package"
            throw NSError(domain: "TrailsLogosClient", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        return data
    }

    // MARK: - Publish Package Archive

    public func publishPackageZip(zipData: Data, publisherAccount: String = "0x0000000000000000000000000000000000000001", operationId: String = UUID().uuidString) async throws -> LogosPublicationReceipt {
        self.isPublishing = true
        defer { self.isPublishing = false }

        let url = baseURL.appendingPathComponent("publications")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        request.setValue(publisherAccount, forHTTPHeaderField: "X-Publisher-Account")
        request.setValue(operationId, forHTTPHeaderField: "X-Operation-Id")
        request.httpBody = zipData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 201) else {
            let msg = String(data: data, encoding: .utf8) ?? "Failed to publish package"
            throw NSError(domain: "TrailsLogosClient", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let receipt = try JSONDecoder().decode(LogosPublicationReceipt.self, from: data)
        self.lastReceipt = receipt
        return receipt
    }
}

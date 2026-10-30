//
//  BookmarksStore.swift
//  Trails
//
//  Local persistence coordinator for bookmarked community trails (PRD v0.4.0 §11).
//  Bookmarking is strictly independent of downloading:
//  - Bookmark: Save a reference for later
//  - Download: Store the package locally
//  - Removing bookmark does not delete downloaded content
//  - Removing download does not remove bookmark
//

import Foundation
import Combine

@MainActor
public final class BookmarksStore: ObservableObject {
    public static let shared = BookmarksStore()

    private let userDefaultsKey = "Trails_Bookmarked_Trail_IDs"
    private let userDefaultsMetaKey = "Trails_Bookmarked_Metadata"

    @Published public private(set) var bookmarkedIds: Set<String> = []
    @Published public private(set) var bookmarkedRecords: [String: DiscoveryRecord] = [:]
    @Published public var toastMessage: String? = nil

    private init() {
        loadFromDisk()
    }

    public func isBookmarked(trailId: String) -> Bool {
        bookmarkedIds.contains(trailId)
    }

    @discardableResult
    public func toggleBookmark(record: DiscoveryRecord) -> Bool {
        if isBookmarked(trailId: record.trailId) {
            removeBookmark(trailId: record.trailId)
            return false
        } else {
            addBookmark(record: record)
            return true
        }
    }

    public func addBookmark(record: DiscoveryRecord) {
        bookmarkedIds.insert(record.trailId)
        bookmarkedRecords[record.trailId] = record
        saveToDisk()
        showToast("Bookmarked. Download to view offline.")
    }

    public func removeBookmark(trailId: String) {
        bookmarkedIds.remove(trailId)
        bookmarkedRecords.removeValue(forKey: trailId)
        saveToDisk()
    }

    public func updateRecordMetadata(_ record: DiscoveryRecord) {
        if bookmarkedIds.contains(record.trailId) {
            bookmarkedRecords[record.trailId] = record
            saveToDisk()
        }
    }

    private func showToast(_ message: String) {
        self.toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.toastMessage == message {
                self.toastMessage = nil
            }
        }
    }

    private func loadFromDisk() {
        if let storedIds = UserDefaults.standard.stringArray(forKey: userDefaultsKey) {
            self.bookmarkedIds = Set(storedIds)
        }
        if let data = UserDefaults.standard.data(forKey: userDefaultsMetaKey),
           let records = try? JSONDecoder().decode([String: DiscoveryRecord].self, from: data) {
            self.bookmarkedRecords = records
        }
    }

    private func saveToDisk() {
        UserDefaults.standard.set(Array(bookmarkedIds), forKey: userDefaultsKey)
        if let data = try? JSONEncoder().encode(bookmarkedRecords) {
            UserDefaults.standard.set(data, forKey: userDefaultsMetaKey)
        }
    }
}

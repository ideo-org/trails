//
//  TrailZipArchiver.swift
//  Trails
//
//  Lightweight, deterministic Swift ZIP archive builder.
//  Packs manifest.json and trail assets into standard zip format for trails.logos publishing.
//

import Foundation

public struct TrailZipArchiver {

    public struct FileEntry {
        public let name: String
        public let data: Data

        public init(name: String, data: Data) {
            self.name = name
            self.data = data
        }
    }

    public static func createZip(entries: [FileEntry]) -> Data {
        var body = Data()
        var centralDirectory = Data()
        var localOffsets: [Int] = []

        for entry in entries {
            let offset = body.count
            localOffsets.append(offset)

            let nameBytes = Array(entry.name.utf8)
            let nameLen = UInt16(nameBytes.count)
            let dataLen = UInt32(entry.data.count)
            let crc = crc32(data: entry.data)

            // Local File Header (PK\x03\x04)
            var localHeader = Data([0x50, 0x4B, 0x03, 0x04])
            var version: UInt16 = 20
            var flags: UInt16 = 0
            var method: UInt16 = 0 // Stored / No compression
            var modTime: UInt16 = 0
            var modDate: UInt16 = 0

            localHeader.append(contentsOf: withUnsafeBytes(of: &version) { Array($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: &flags) { Array($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: &method) { Array($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: &modTime) { Array($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: &modDate) { Array($0) })
            var crcMutable = crc
            localHeader.append(contentsOf: withUnsafeBytes(of: &crcMutable) { Array($0) })
            var dataLenMutable = dataLen
            localHeader.append(contentsOf: withUnsafeBytes(of: &dataLenMutable) { Array($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: &dataLenMutable) { Array($0) })
            var nameLenMutable = nameLen
            localHeader.append(contentsOf: withUnsafeBytes(of: &nameLenMutable) { Array($0) })
            var extraLen: UInt16 = 0
            localHeader.append(contentsOf: withUnsafeBytes(of: &extraLen) { Array($0) })
            localHeader.append(contentsOf: nameBytes)

            body.append(localHeader)
            body.append(entry.data)
        }

        let cdOffset = UInt32(body.count)

        for (idx, entry) in entries.enumerated() {
            let nameBytes = Array(entry.name.utf8)
            let nameLen = UInt16(nameBytes.count)
            let dataLen = UInt32(entry.data.count)
            let crc = crc32(data: entry.data)
            let offset = UInt32(localOffsets[idx])

            // Central Directory Header (PK\x01\x02)
            var cd = Data([0x50, 0x4B, 0x01, 0x02])
            var versionMadeBy: UInt16 = 20
            var versionNeeded: UInt16 = 20
            var flags: UInt16 = 0
            var method: UInt16 = 0
            var modTime: UInt16 = 0
            var modDate: UInt16 = 0

            cd.append(contentsOf: withUnsafeBytes(of: &versionMadeBy) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: &versionNeeded) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: &flags) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: &method) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: &modTime) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: &modDate) { Array($0) })
            var crcMutable = crc
            cd.append(contentsOf: withUnsafeBytes(of: &crcMutable) { Array($0) })
            var dataLenMutable = dataLen
            cd.append(contentsOf: withUnsafeBytes(of: &dataLenMutable) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: &dataLenMutable) { Array($0) })
            var nameLenMutable = nameLen
            cd.append(contentsOf: withUnsafeBytes(of: &nameLenMutable) { Array($0) })
            var extraLen: UInt16 = 0
            cd.append(contentsOf: withUnsafeBytes(of: &extraLen) { Array($0) })
            var commentLen: UInt16 = 0
            cd.append(contentsOf: withUnsafeBytes(of: &commentLen) { Array($0) })
            var diskStart: UInt16 = 0
            cd.append(contentsOf: withUnsafeBytes(of: &diskStart) { Array($0) })
            var intAttr: UInt16 = 0
            cd.append(contentsOf: withUnsafeBytes(of: &intAttr) { Array($0) })
            var extAttr: UInt32 = 0
            cd.append(contentsOf: withUnsafeBytes(of: &extAttr) { Array($0) })
            var offMutable = offset
            cd.append(contentsOf: withUnsafeBytes(of: &offMutable) { Array($0) })
            cd.append(contentsOf: nameBytes)

            centralDirectory.append(cd)
        }

        let cdSize = UInt32(centralDirectory.count)

        // End of Central Directory Record (PK\x05\x06)
        var eocd = Data([0x50, 0x4B, 0x05, 0x06])
        var diskNum: UInt16 = 0
        var cdDisk: UInt16 = 0
        var recordCount = UInt16(entries.count)

        eocd.append(contentsOf: withUnsafeBytes(of: &diskNum) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: &cdDisk) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: &recordCount) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: &recordCount) { Array($0) })
        var cdSizeMutable = cdSize
        eocd.append(contentsOf: withUnsafeBytes(of: &cdSizeMutable) { Array($0) })
        var cdOffsetMutable = cdOffset
        eocd.append(contentsOf: withUnsafeBytes(of: &cdOffsetMutable) { Array($0) })
        var commentLength: UInt16 = 0
        eocd.append(contentsOf: withUnsafeBytes(of: &commentLength) { Array($0) })

        var completeArchive = Data()
        completeArchive.append(body)
        completeArchive.append(centralDirectory)
        completeArchive.append(eocd)
        return completeArchive
    }

    private static func crc32(data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            var c = UInt32(byte) ^ (crc & 0xFF)
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            crc = c ^ (crc >> 8)
        }
        return ~crc
    }
}

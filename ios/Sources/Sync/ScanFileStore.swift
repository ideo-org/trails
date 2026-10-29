import Foundation

enum ScanFileStore {
    nonisolated static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    nonisolated static func fileURL(fileName: String) -> URL {
        documentsDirectory.appendingPathComponent(fileName)
    }

    nonisolated static func filePath(fileName: String) -> String {
        fileURL(fileName: fileName).path
    }

    nonisolated static func loadImageData(fileName: String) -> Data? {
        try? Data(contentsOf: fileURL(fileName: fileName))
    }

    static func deleteLocalFiles(for scan: Scan) {
        let fileManager = FileManager.default
        let plyNames = Set(scan.plyFileNames + [scan.plyFileName])
        let snapNames = Set(scan.snapFileNames + scan.snapshots.map(\.fileName))
        let thumbnailNames = scan.scanParts.compactMap(\.thumbnailFileName)
        let gaussianNames = [
            scan.gaussianCaptureManifestFileName,
            scan.gaussianAssetManifestFileName,
            scan.gaussianSplatFileName,
            scan.gaussianPLYFileName,
            scan.gaussianSPZFileName,
            scan.gaussianSOGFileName
        ].compactMap { $0 }
        let urls = plyNames.map(fileURL(fileName:))
            + snapNames.map(fileURL(fileName:))
            + thumbnailNames.map(fileURL(fileName:))
            + gaussianNames.map(fileURL(fileName:))
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }

        if let manifestFileName = scan.gaussianCaptureManifestFileName {
            let bundleURL = fileURL(fileName: manifestFileName).deletingLastPathComponent()
            if fileManager.fileExists(atPath: bundleURL.path) {
                try? fileManager.removeItem(at: bundleURL)
            }
        }
    }
}

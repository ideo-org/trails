import Foundation
import SwiftUI
import WebKit
import UIKit

struct TrailsWebSplatView: UIViewRepresentable {
    private static let viewerScheme = "trails-viewer"
    private static let sharedProcessPool = WKProcessPool()

    let assetFileName: String
    let showsGrid: Bool
    let resetViewToken: Int
    let captureThumbnailToken: Int
    var onViewerSnapshot: ((UIImage) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.processPool = Self.sharedProcessPool
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: Self.viewerScheme)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.075, green: 0.082, blue: 0.092, alpha: 1)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.configure(
            webView,
            assetFileName: assetFileName,
            showsGrid: showsGrid,
            resetViewToken: resetViewToken,
            captureThumbnailToken: captureThumbnailToken,
            onViewerSnapshot: onViewerSnapshot
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.configure(
            webView,
            assetFileName: assetFileName,
            showsGrid: showsGrid,
            resetViewToken: resetViewToken,
            captureThumbnailToken: captureThumbnailToken,
            onViewerSnapshot: onViewerSnapshot
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let schemeHandler = TrailsViewerSchemeHandler()
        private weak var webView: WKWebView?
        private var loadedAssetFileName: String?
        private var loadedAssetCacheKey: String?
        private var lastShowsGrid: Bool?
        private var lastResetViewToken = 0
        private var lastCaptureThumbnailToken = 0
        private var pendingResetAfterLoad = false
        private var onViewerSnapshot: ((UIImage) -> Void)?

        func configure(
            _ webView: WKWebView,
            assetFileName: String,
            showsGrid: Bool,
            resetViewToken: Int,
            captureThumbnailToken: Int,
            onViewerSnapshot: ((UIImage) -> Void)?
        ) {
            self.webView = webView
            self.onViewerSnapshot = onViewerSnapshot

            let sourceAssetURL = ScanFileStore.fileURL(fileName: assetFileName)
            let assetCacheKey = Self.cacheKey(for: sourceAssetURL)
            if loadedAssetFileName != assetFileName || loadedAssetCacheKey != assetCacheKey {
                loadedAssetFileName = assetFileName
                loadedAssetCacheKey = assetCacheKey
                lastShowsGrid = showsGrid
                lastResetViewToken = resetViewToken
                lastCaptureThumbnailToken = captureThumbnailToken
                load(
                    assetFileName: assetFileName,
                    showsGrid: showsGrid,
                    cacheKey: assetCacheKey,
                    in: webView
                )
                return
            }

            if lastShowsGrid != showsGrid {
                lastShowsGrid = showsGrid
                evaluate("window.trailsSetGrid && window.trailsSetGrid(\(showsGrid ? "true" : "false"));")
            }

            if lastResetViewToken != resetViewToken {
                lastResetViewToken = resetViewToken
                evaluate("window.trailsResetView && window.trailsResetView();")
            }

            if lastCaptureThumbnailToken != captureThumbnailToken {
                lastCaptureThumbnailToken = captureThumbnailToken
                captureSnapshot()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if pendingResetAfterLoad {
                pendingResetAfterLoad = false
                evaluate("window.trailsResetView && window.trailsResetView();")
            }
        }

        private func load(
            assetFileName: String,
            showsGrid: Bool,
            cacheKey: String,
            in webView: WKWebView
        ) {
            do {
                guard let playCanvasURL = Self.bundledPlayCanvasURL() else {
                    throw NSError(
                        domain: "TrailsWebSplatView",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "PlayCanvas runtime is missing from the app bundle."]
                    )
                }

                let sourceAssetURL = ScanFileStore.fileURL(fileName: assetFileName)
                guard FileManager.default.fileExists(atPath: sourceAssetURL.path) else {
                    throw NSError(
                        domain: "TrailsWebSplatView",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "3DGS asset file is missing."]
                    )
                }

                schemeHandler.configure(assetFileName: assetFileName, playCanvasURL: playCanvasURL)
                let viewerURL = Self.viewerURL(
                    assetFileName: assetFileName,
                    showsGrid: showsGrid,
                    cacheKey: cacheKey
                )
                pendingResetAfterLoad = true
                webView.load(URLRequest(url: viewerURL))
            } catch {
                webView.loadHTMLString(Self.errorHTML(message: error.localizedDescription), baseURL: nil)
            }
        }

        private func evaluate(_ script: String) {
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        private func captureSnapshot() {
            guard let webView else { return }
            let configuration = WKSnapshotConfiguration()
            configuration.rect = webView.bounds
            webView.takeSnapshot(with: configuration) { [onViewerSnapshot] image, _ in
                guard let image else { return }
                DispatchQueue.main.async {
                    onViewerSnapshot?(image)
                }
            }
        }

        private static func viewerURL(assetFileName: String, showsGrid: Bool, cacheKey: String) -> URL {
            var components = URLComponents()
            components.scheme = TrailsWebSplatView.viewerScheme
            components.host = "local"
            components.path = "/index.html"
            components.queryItems = [
                URLQueryItem(name: "asset", value: "assets/\(viewerAssetFileName(from: assetFileName))?v=\(cacheKey)"),
                URLQueryItem(name: "grid", value: showsGrid ? "1" : "0")
            ]
            return components.url ?? URL(string: "\(TrailsWebSplatView.viewerScheme)://local/index.html")!
        }

        private static func viewerAssetFileName(from assetFileName: String) -> String {
            let fileName = URL(fileURLWithPath: assetFileName).lastPathComponent
            return fileName.isEmpty ? "scan.ply" : fileName
        }

        private static func cacheKey(for url: URL) -> String {
            let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
            let values = try? url.resourceValues(forKeys: keys)
            let fileSize = values?.fileSize ?? 0
            let modifiedAt = Int((values?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000)
            return "\(fileSize)-\(modifiedAt)"
        }

        private static func bundledPlayCanvasURL() -> URL? {
            let bundleCandidates: [URL?] = [
                Bundle.main.url(forResource: "playcanvas.min", withExtension: "js"),
                Bundle.main.url(forResource: "playcanvas.min", withExtension: "js", subdirectory: "Trails/WebViewer"),
                Bundle.main.url(forResource: "playcanvas.min", withExtension: "js", subdirectory: "WebViewer")
            ]
            if let directMatch = bundleCandidates.compactMap({ $0 }).first {
                return directMatch
            }

            guard let resourceURL = Bundle.main.resourceURL,
                  let enumerator = FileManager.default.enumerator(
                    at: resourceURL,
                    includingPropertiesForKeys: nil
                  ) else {
                return nil
            }

            for case let url as URL in enumerator where url.lastPathComponent == "playcanvas.min.js" {
                return url
            }
            return nil
        }

        final class TrailsViewerSchemeHandler: NSObject, WKURLSchemeHandler {
            private struct ViewerConfiguration {
                let assetFileName: String
                let playCanvasURL: URL
            }

            private enum ResourceCachePolicy {
                case noStore
                case immutable

                var headerValue: String {
                    switch self {
                    case .noStore:
                        return "no-store"
                    case .immutable:
                        return "public, max-age=31536000, immutable"
                    }
                }
            }

            private let queue = DispatchQueue(label: "com.trails.web-viewer.scheme", qos: .userInitiated)
            private let lock = NSLock()
            private var configuration: ViewerConfiguration?
            private var activeTaskIDs = Set<ObjectIdentifier>()

            func configure(assetFileName: String, playCanvasURL: URL) {
                lock.lock()
                configuration = ViewerConfiguration(
                    assetFileName: assetFileName,
                    playCanvasURL: playCanvasURL
                )
                lock.unlock()
            }

            func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
                let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
                let configuration = currentConfiguration()

                lock.lock()
                activeTaskIDs.insert(taskID)
                lock.unlock()

                queue.async { [weak self] in
                    self?.respond(to: urlSchemeTask, taskID: taskID, configuration: configuration)
                }
            }

            func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
                let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
                finishTask(taskID)
            }

            private func respond(
                to urlSchemeTask: WKURLSchemeTask,
                taskID: ObjectIdentifier,
                configuration: ViewerConfiguration?
            ) {
                do {
                    guard let configuration else {
                        throw Self.makeError("PlayCanvas viewer was not configured.")
                    }
                    guard let url = urlSchemeTask.request.url else {
                        throw Self.makeError("Viewer resource request is missing a URL.")
                    }

                    switch url.path {
                    case "", "/", "/index.html":
                        try respond(
                            with: Data(Coordinator.indexHTML.utf8),
                            mimeType: "text/html",
                            cachePolicy: .noStore,
                            to: urlSchemeTask,
                            taskID: taskID
                        )
                    case "/playcanvas.min.js":
                        try respond(
                            with: Self.cachedPlayCanvasData(from: configuration.playCanvasURL),
                            mimeType: "text/javascript",
                            cachePolicy: .immutable,
                            to: urlSchemeTask,
                            taskID: taskID
                        )
                    default:
                        if url.path.hasPrefix("/assets/") {
                            try respondWithAsset(
                                requestURL: url,
                                configuration: configuration,
                                to: urlSchemeTask,
                                taskID: taskID
                            )
                        } else {
                            throw Self.makeError("Unknown viewer resource: \(url.path)")
                        }
                    }
                } catch {
                    failTask(urlSchemeTask, taskID: taskID, error: error)
                }
            }

            private func respondWithAsset(
                requestURL: URL,
                configuration: ViewerConfiguration,
                to urlSchemeTask: WKURLSchemeTask,
                taskID: ObjectIdentifier
            ) throws {
                let requestedFileName = requestURL.lastPathComponent.removingPercentEncoding ?? requestURL.lastPathComponent
                let expectedFileName = Coordinator.viewerAssetFileName(from: configuration.assetFileName)
                guard requestedFileName == expectedFileName else {
                    throw Self.makeError("Blocked viewer asset request.")
                }

                let assetURL = ScanFileStore.fileURL(fileName: configuration.assetFileName)
                guard FileManager.default.fileExists(atPath: assetURL.path) else {
                    throw Self.makeError("Native 3DGS asset file is missing.")
                }

                try respond(
                    withFileAt: assetURL,
                    mimeType: "application/octet-stream",
                    cachePolicy: .immutable,
                    to: urlSchemeTask,
                    taskID: taskID
                )
            }

            private func respond(
                with data: Data,
                mimeType: String,
                cachePolicy: ResourceCachePolicy,
                to urlSchemeTask: WKURLSchemeTask,
                taskID: ObjectIdentifier
            ) throws {
                guard let url = urlSchemeTask.request.url else {
                    throw Self.makeError("Viewer resource request is missing a URL.")
                }
                guard isActive(taskID) else { return }

                urlSchemeTask.didReceive(Self.response(
                    url: url,
                    mimeType: mimeType,
                    contentLength: data.count,
                    cachePolicy: cachePolicy
                ))
                guard isActive(taskID) else { return }
                urlSchemeTask.didReceive(data)
                guard isActive(taskID) else { return }
                urlSchemeTask.didFinish()
                finishTask(taskID)
            }

            private func respond(
                withFileAt fileURL: URL,
                mimeType: String,
                cachePolicy: ResourceCachePolicy,
                to urlSchemeTask: WKURLSchemeTask,
                taskID: ObjectIdentifier
            ) throws {
                guard let requestURL = urlSchemeTask.request.url else {
                    throw Self.makeError("Viewer resource request is missing a URL.")
                }

                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = values.fileSize ?? -1
                guard fileSize >= 0 else {
                    throw Self.makeError("Viewer resource has no readable file size.")
                }

                let fileHandle = try FileHandle(forReadingFrom: fileURL)
                defer { try? fileHandle.close() }

                guard isActive(taskID) else { return }
                urlSchemeTask.didReceive(Self.response(
                    url: requestURL,
                    mimeType: mimeType,
                    contentLength: fileSize,
                    cachePolicy: cachePolicy
                ))

                while isActive(taskID) {
                    let chunk = try fileHandle.read(upToCount: 1024 * 1024) ?? Data()
                    if chunk.isEmpty { break }
                    urlSchemeTask.didReceive(chunk)
                }

                guard isActive(taskID) else { return }
                urlSchemeTask.didFinish()
                finishTask(taskID)
            }

            private func currentConfiguration() -> ViewerConfiguration? {
                lock.lock()
                let configuration = configuration
                lock.unlock()
                return configuration
            }

            private func isActive(_ taskID: ObjectIdentifier) -> Bool {
                lock.lock()
                let active = activeTaskIDs.contains(taskID)
                lock.unlock()
                return active
            }

            private func finishTask(_ taskID: ObjectIdentifier) {
                lock.lock()
                activeTaskIDs.remove(taskID)
                lock.unlock()
            }

            private func failTask(_ urlSchemeTask: WKURLSchemeTask, taskID: ObjectIdentifier, error: Error) {
                guard isActive(taskID) else { return }
                urlSchemeTask.didFailWithError(error)
                finishTask(taskID)
            }

            private static func response(
                url: URL,
                mimeType: String,
                contentLength: Int,
                cachePolicy: ResourceCachePolicy
            ) -> URLResponse {
                let headers = [
                    "Content-Type": mimeType,
                    "Content-Length": "\(contentLength)",
                    "Cache-Control": cachePolicy.headerValue
                ]
                return HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                ) ?? URLResponse(
                    url: url,
                    mimeType: mimeType,
                    expectedContentLength: contentLength,
                    textEncodingName: nil
                )
            }

            private static func makeError(_ message: String) -> NSError {
                NSError(
                    domain: "TrailsViewerSchemeHandler",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            private static let playCanvasCache = ResourceDataCache()

            private static func cachedPlayCanvasData(from url: URL) throws -> Data {
                try playCanvasCache.data(from: url)
            }
        }

        private final class ResourceDataCache {
            private let lock = NSLock()
            private var cachedDataByPath: [String: Data] = [:]

            func data(from url: URL) throws -> Data {
                let key = url.path
                lock.lock()
                if let cachedData = cachedDataByPath[key] {
                    lock.unlock()
                    return cachedData
                }
                lock.unlock()

                let data = try Data(contentsOf: url, options: .mappedIfSafe)

                lock.lock()
                cachedDataByPath[key] = data
                lock.unlock()
                return data
            }
        }

        private static func errorHTML(message: String) -> String {
            """
            <!doctype html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
              <style>
                html, body { margin: 0; height: 100%; background: #15171a; color: white; font: 15px -apple-system, BlinkMacSystemFont, sans-serif; }
                body { display: grid; place-items: center; padding: 24px; box-sizing: border-box; text-align: center; }
              </style>
            </head>
            <body>Unable to open PlayCanvas viewer.<br>\(message)</body>
            </html>
            """
        }

        private static let indexHTML = #"""
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
          <style>
            html, body, canvas {
              margin: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: #13151a;
              touch-action: none;
              -webkit-user-select: none;
              user-select: none;
            }
            canvas {
              filter: brightness(1.06) contrast(1.035) saturate(1.035);
            }
            #status {
              position: fixed;
              left: 50%;
              top: 50%;
              transform: translate(-50%, -50%);
              padding: 9px 13px;
              border: 1px solid rgba(255, 255, 255, 0.16);
              border-radius: 999px;
              background: rgba(0, 0, 0, 0.48);
              color: rgba(255, 255, 255, 0.86);
              display: none;
              font: 600 13px -apple-system, BlinkMacSystemFont, sans-serif;
              letter-spacing: 0;
              pointer-events: none;
            }
          </style>
        </head>
        <body>
          <canvas id="application"></canvas>
          <div id="status"></div>
          <script src="playcanvas.min.js?v=2.18.1"></script>
          <script>
            (() => {
              const status = document.getElementById('status');
              const canvas = document.getElementById('application');
              const params = new URLSearchParams(window.location.search);
              const assetUrl = params.get('asset');
              let showsGrid = params.get('grid') !== '0';

              const setStatus = (message) => {
                status.textContent = message;
                status.style.display = message ? 'block' : 'none';
              };
              const loadingTimer = window.setTimeout(() => setStatus('Loading PlayCanvas viewer'), 220);
              const clearLoading = () => {
                window.clearTimeout(loadingTimer);
              };

              const notifyFailure = (message) => {
                clearLoading();
                setStatus(message);
              };

              const describeError = (error) => {
                if (!error) return 'Unknown error';
                if (error.message) return error.message;
                return String(error);
              };

              if (!window.pc) {
                notifyFailure('PlayCanvas did not load');
                return;
              }
              if (!assetUrl) {
                notifyFailure('No 3DGS asset found');
                return;
              }

              const app = new pc.Application(canvas, {
                mouse: new pc.Mouse(canvas),
                touch: new pc.TouchDevice(canvas),
                keyboard: new pc.Keyboard(window),
                graphicsDeviceOptions: {
                  antialias: false,
                  powerPreference: 'high-performance'
                }
              });

              const targetPixelRatio = () => Math.min(Math.max(window.devicePixelRatio || 1, 1), 2.0);
              const applyPixelRatio = () => {
                if (app.graphicsDevice && 'maxPixelRatio' in app.graphicsDevice) {
                  app.graphicsDevice.maxPixelRatio = targetPixelRatio();
                }
              };

              window.addEventListener('error', (event) => {
                notifyFailure(`PlayCanvas viewer error: ${describeError(event.error || event.message)}`);
              });
              window.addEventListener('unhandledrejection', (event) => {
                notifyFailure(`PlayCanvas viewer error: ${describeError(event.reason)}`);
              });

              applyPixelRatio();
              app.setCanvasFillMode(pc.FILLMODE_FILL_WINDOW);
              app.setCanvasResolution(pc.RESOLUTION_AUTO);
              app.scene.ambientLight = new pc.Color(0.68, 0.66, 0.61);
              if ('toneMapping' in app.scene && typeof pc.TONEMAP_NEUTRAL !== 'undefined') {
                app.scene.toneMapping = pc.TONEMAP_NEUTRAL;
              }
              if ('exposure' in app.scene) {
                app.scene.exposure = 1.08;
              }
              app.start();

              const camera = new pc.Entity('Camera');
              camera.addComponent('camera', {
                clearColor: new pc.Color(0.075, 0.082, 0.092),
                fov: 50,
                nearClip: 0.02,
                farClip: 1000
              });
              app.root.addChild(camera);

              const addDirectionalLight = (name, color, intensity, angles) => {
                const light = new pc.Entity(name);
                light.addComponent('light', {
                  type: 'directional',
                  color,
                  intensity,
                  castShadows: false
                });
                light.setEulerAngles(angles.x, angles.y, angles.z);
                app.root.addChild(light);
              };

              addDirectionalLight(
                'Key Light',
                new pc.Color(1.0, 0.96, 0.88),
                1.05,
                { x: 42, y: 32, z: 0 }
              );
              addDirectionalLight(
                'Fill Light',
                new pc.Color(0.60, 0.72, 1.0),
                0.34,
                { x: 8, y: -118, z: 0 }
              );
              addDirectionalLight(
                'Rim Light',
                new pc.Color(0.75, 0.86, 1.0),
                0.42,
                { x: -36, y: 145, z: 0 }
              );

              const target = new pc.Vec3(0, 0, 0);
              const sceneCenter = new pc.Vec3(0, 0, 0);
              let yaw = -0.72;
              let pitch = -0.18;
              let distance = 3.0;
              let minDistance = 0.12;
              let maxDistance = 40.0;
              let sceneRadius = 1.0;
              let maxPanRadius = 1.2;
              const gridColor = new pc.Color(0.36, 0.39, 0.43, 0.38);
              const gridPositions = [];

              const clampPitch = () => {
                pitch = Math.max(-1.15, Math.min(1.08, pitch));
              };

              const clampTarget = () => {
                const offset = target.clone().sub(sceneCenter);
                const length = offset.length();
                if (length > maxPanRadius && length > 0.0001) {
                  offset.mulScalar(maxPanRadius / length);
                  target.copy(sceneCenter).add(offset);
                }
              };

              const updateCameraClip = () => {
                if (!camera.camera) return;
                camera.camera.farClip = Math.min(
                  Math.max((distance + sceneRadius * 3.5) * 1.35, 80.0),
                  5000.0
                );
              };

              const updateCamera = () => {
                clampPitch();
                distance = Math.max(minDistance, Math.min(maxDistance, distance));
                clampTarget();
                updateCameraClip();
                const cp = Math.cos(pitch);
                const eye = new pc.Vec3(
                  target.x + Math.sin(yaw) * cp * distance,
                  target.y + Math.sin(pitch) * distance,
                  target.z + Math.cos(yaw) * cp * distance
                );
                camera.setPosition(eye);
                camera.lookAt(target);
              };

              const fitBounds = (resource) => {
                const aabb = resource && resource.aabb;
                if (!aabb) {
                  updateCamera();
                  return;
                }
                sceneCenter.copy(aabb.center);
                target.copy(sceneCenter);
                const half = aabb.halfExtents;
                sceneRadius = Math.max(0.12, Math.sqrt(half.x * half.x + half.y * half.y + half.z * half.z));
                distance = Math.max(sceneRadius * 2.8, 1.05);
                minDistance = Math.max(sceneRadius * 0.08, 0.12);
                maxDistance = Math.min(Math.max(sceneRadius * 6.0, 4.0), 90.0);
                maxPanRadius = Math.max(sceneRadius * 1.15, 0.55);
                yaw = -0.68;
                pitch = -0.22;
                rebuildGrid();
                updateCamera();
              };

              const rebuildGrid = () => {
                gridPositions.length = 0;
                const span = Math.max(1, Math.ceil(sceneRadius * 1.6));
                const step = Math.max(0.1, Math.pow(10, Math.floor(Math.log10(span))) / 2);
                const size = Math.ceil(span / step) * step;
                const y = target.y - sceneRadius * 0.68;
                for (let v = -size; v <= size + 0.0001; v += step) {
                  gridPositions.push(new pc.Vec3(target.x - size, y, target.z + v));
                  gridPositions.push(new pc.Vec3(target.x + size, y, target.z + v));
                  gridPositions.push(new pc.Vec3(target.x + v, y, target.z - size));
                  gridPositions.push(new pc.Vec3(target.x + v, y, target.z + size));
                }
              };

              window.trailsSetGrid = (value) => {
                showsGrid = !!value;
              };

              window.trailsResetView = () => {
                yaw = -0.68;
                pitch = -0.22;
                target.copy(sceneCenter);
                distance = Math.max(sceneRadius * 2.8, 1.05);
                updateCamera();
              };

              let activePointer = null;
              let lastX = 0;
              let lastY = 0;
              let panMode = false;

              const panCamera = (dx, dy, strength = 1.0) => {
                const position = camera.getPosition();
                const forward = target.clone().sub(position).normalize();
                const right = new pc.Vec3().cross(forward, pc.Vec3.UP).normalize();
                const up = new pc.Vec3().cross(right, forward).normalize();
                const scale = distance / Math.max(canvas.clientHeight, 1) * 1.35 * strength;
                target.add(right.mulScalar(-dx * scale));
                target.add(up.mulScalar(dy * scale));
                clampTarget();
              };

              canvas.addEventListener('pointerdown', (event) => {
                activePointer = event.pointerId;
                lastX = event.clientX;
                lastY = event.clientY;
                panMode = event.shiftKey || event.button === 1 || event.button === 2;
                canvas.setPointerCapture(event.pointerId);
              });

              canvas.addEventListener('pointermove', (event) => {
                if (activePointer !== event.pointerId) return;
                const dx = event.clientX - lastX;
                const dy = event.clientY - lastY;
                lastX = event.clientX;
                lastY = event.clientY;
                if (panMode) {
                  panCamera(dx, dy);
                } else {
                  yaw -= dx * 0.0065;
                  pitch -= dy * 0.0048;
                }
                updateCamera();
              });

              canvas.addEventListener('pointerup', (event) => {
                if (activePointer === event.pointerId) {
                  activePointer = null;
                }
              });
              canvas.addEventListener('contextmenu', (event) => event.preventDefault());

              canvas.addEventListener('wheel', (event) => {
                event.preventDefault();
                const zoom = Math.exp(event.deltaY * 0.0014);
                distance *= zoom;
                updateCamera();
              }, { passive: false });

              let previousTouchDistance = 0;
              let previousTouchCenter = null;
              canvas.addEventListener('touchstart', (event) => {
                if (event.touches.length === 2) {
                  const a = event.touches[0];
                  const b = event.touches[1];
                  previousTouchDistance = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
                  previousTouchCenter = {
                    x: (a.clientX + b.clientX) * 0.5,
                    y: (a.clientY + b.clientY) * 0.5
                  };
                }
              }, { passive: false });

              canvas.addEventListener('touchmove', (event) => {
                event.preventDefault();
                if (event.touches.length === 2) {
                  const a = event.touches[0];
                  const b = event.touches[1];
                  const nextDistance = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
                  const nextCenter = {
                    x: (a.clientX + b.clientX) * 0.5,
                    y: (a.clientY + b.clientY) * 0.5
                  };
                  if (previousTouchDistance > 0) {
                    distance *= previousTouchDistance / Math.max(nextDistance, 1);
                  }
                  if (previousTouchCenter) {
                    const centerDx = nextCenter.x - previousTouchCenter.x;
                    const centerDy = nextCenter.y - previousTouchCenter.y;
                    if (Math.hypot(centerDx, centerDy) > 3) {
                      panCamera(centerDx, centerDy, 0.16);
                    }
                  }
                  previousTouchDistance = nextDistance;
                  previousTouchCenter = nextCenter;
                  updateCamera();
                }
              }, { passive: false });

              const clearPinchState = (event) => {
                if (event.touches.length < 2) {
                  previousTouchDistance = 0;
                  previousTouchCenter = null;
                }
              };
              canvas.addEventListener('touchend', clearPinchState, { passive: false });
              canvas.addEventListener('touchcancel', clearPinchState, { passive: false });

              app.on('update', () => {
                if (showsGrid && gridPositions.length > 0) {
                  app.drawLines(gridPositions, gridColor, true);
                }
              });

              const asset = new pc.Asset('scan', 'gsplat', { url: assetUrl });
              asset.on('load', () => {
                try {
                  const scan = new pc.Entity('Scan');
                  scan.addComponent('gsplat', {
                    asset: asset.id,
                    highQualitySH: true
                  });
                  app.root.addChild(scan);
                  fitBounds(asset.resource);
                  clearLoading();
                  setStatus('');
                } catch (error) {
                  notifyFailure(`3DGS renderer failed: ${describeError(error)}`);
                }
              });
              asset.on('error', (error) => {
                notifyFailure(`3DGS asset failed: ${describeError(error)}`);
              });
              app.assets.add(asset);
              app.assets.load(asset);

              window.addEventListener('resize', () => {
                applyPixelRatio();
                app.resizeCanvas();
                updateCamera();
              });
              updateCamera();
            })();
          </script>
        </body>
        </html>
        """#
    }
}

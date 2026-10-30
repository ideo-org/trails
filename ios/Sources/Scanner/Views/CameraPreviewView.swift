//
//  CameraPreviewView.swift
//  Trails
//
//  SwiftUI UIViewRepresentable for live AVCaptureVideoPreviewLayer
//  with tap-to-focus animation and pinch-to-zoom (PRD v0.2.1 §10.1).
//

import SwiftUI
import AVFoundation

public struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraEngine: CameraCaptureEngine

    public init(cameraEngine: CameraCaptureEngine) {
        self.cameraEngine = cameraEngine
    }

    public func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = cameraEngine.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.onTapToFocus = { point in
            let devicePoint = view.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: point)
            cameraEngine.focusAndExpose(at: devicePoint)
        }
        view.onPinchZoom = { scale in
            let newFactor = cameraEngine.zoomFactor * scale
            cameraEngine.setZoom(factor: newFactor)
        }
        return view
    }

    public func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.videoPreviewLayer.session != cameraEngine.session {
            uiView.videoPreviewLayer.session = cameraEngine.session
        }
    }

    public static func dismantleUIView(_ uiView: PreviewUIView, coordinator: ()) {
        uiView.videoPreviewLayer.session = nil
    }
}

public final class PreviewUIView: UIView {
    public var onTapToFocus: ((CGPoint) -> Void)?
    public var onPinchZoom: ((CGFloat) -> Void)?

    private let focusIndicator: UIView = {
        let indicator = UIView(frame: CGRect(x: 0, y: 0, width: 68, height: 68))
        indicator.layer.borderColor = UIColor(red: 0.71, green: 0.60, blue: 0.35, alpha: 0.95).cgColor
        indicator.layer.borderWidth = 1.5
        indicator.layer.cornerRadius = 10
        indicator.alpha = 0
        return indicator
    }()

    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
        addSubview(focusIndicator)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
        addSubview(focusIndicator)
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showFocusIndicator(at: location)
        onTapToFocus?(location)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .changed {
            onPinchZoom?(gesture.scale)
            gesture.scale = 1.0
        }
    }

    private func showFocusIndicator(at point: CGPoint) {
        focusIndicator.center = point
        focusIndicator.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        focusIndicator.alpha = 1.0

        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseOut, animations: {
            self.focusIndicator.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.25, delay: 0.8, options: .curveEaseIn, animations: {
                self.focusIndicator.alpha = 0
            })
        }
    }
}

// =================================================================
// FILE 2: ContentView.swift
// Replace the contents of the default ContentView.swift
// =================================================================
// This file now contains the main SwiftUI view AND the UIKit views
// responsible for rendering the camera feed and bounding boxes correctly.

import SwiftUI
import Vision
import AVFoundation

// A custom UIView for drawing the bounding boxes. This is more reliable
// than SwiftUI for this use case because its coordinate system is
// directly tied to the camera preview layer's frame.
class DrawingView: UIView {
    var orientation: CGImagePropertyOrientation
    var faces: [ASD.SendableSpeaker] = [] {
        // When this property is set, redraw the view.
        didSet {
            // Must be called on the main thread.
            DispatchQueue.main.async {
                self.setNeedsDisplay()
            }
        }
    }

    var drawRect: CGRect = .zero
    var scale: CGSize = .zero
    var videoSize: CGSize = .zero
    
    var startTime: Double
    
    init(frame: CGRect, videoSize: CGSize, orientation: CGImagePropertyOrientation) {
        self.startTime = Date().timeIntervalSince1970
        self.orientation = orientation
        super.init(frame: frame)
        backgroundColor = .clear // Make it transparent
        isOpaque = false
        
        let videoAspectRatio = videoSize.width / videoSize.height
        let frameAspectRatio = self.bounds.width / self.bounds.height
        print("Bounds: \(self.bounds)")
        
        if (videoAspectRatio > frameAspectRatio) {
            // video is too wide -> fix x-axis
            let drawingWidth = self.bounds.height * videoAspectRatio
            self.drawRect = CGRect(
                x: (self.bounds.width - drawingWidth) / 2,
                y: 0,
                width: drawingWidth,
                height: self.bounds.height
            )
        } else {
            // video is too tall -> fix y-axis
            let drawingHeight = self.bounds.width / videoAspectRatio
            self.drawRect = CGRect(
                x: 0,
                y: (self.bounds.height - drawingHeight) / 2,
                width: self.bounds.width,
                height: drawingHeight
            )
        }
        
        self.scale = CGSize(
            width: self.drawRect.width,
            height: self.drawRect.height
        )
        self.videoSize = videoSize
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let blackoutRect = CGRect(x: 0, y: 0, width: self.bounds.width, height: self.bounds.height)
        
        var cutout = CGPath(rect: CGRect.zero, transform: nil)
        
        context.setLineWidth(3)
        
        struct Caption {
            let text: NSString
            let position: CGPoint
            let attributes: [NSAttributedString.Key: Any]
        }
        
        var captions: [Caption] = []
        
        for face in faces {
            if face.status == .active {
                if face.misses > 0 {
                    context.setStrokeColor(UIColor.yellow.cgColor)
                } else {
                    context.setStrokeColor(UIColor.green.cgColor)
                }
            } else {
                context.setStrokeColor(UIColor.orange.cgColor)
            }
            
            if face.score > 0 {
                context.setLineWidth(10)
            } else {
                context.setLineWidth(3)
            }
            let box = face.rect
            // print("\(Date().timeIntervalSince1970 - self.startTime),\(box.midX),\(box.midY),\(box.width * box.height),\(box.width / box.height)")
            // Here, self.bounds is the frame of this view, which is sized to match the preview layer.
            
            
            // Flip the Y-coordinate because Vision's origin is bottom-left, and UIKit's is top-left.

            let flippedRect = CGRect(
                x: drawRect.origin.x + box.minX * scale.width,
                y: drawRect.origin.y + box.minY * scale.height,
                width: box.width * scale.width,
                height: box.height * scale.height
            )
            
            context.stroke(flippedRect)
            
            // write the ID above the rectangle
            let idText = face.string as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.green
            ]

            let textSize = idText.size(withAttributes: attributes)
            let textOrigin = CGPoint(
                x: flippedRect.origin.x,
                y: flippedRect.origin.y - textSize.height - 2 // small gap above box
            )
            captions.append(.init(text: idText, position: textOrigin, attributes: attributes))
            
            let rectPath = CGPath(rect: flippedRect, transform: nil)
            cutout = cutout.union(rectPath)
        }
        
        let blackoutPath = CGPath(rect: blackoutRect, transform: nil).subtracting(cutout)
        context.addPath(blackoutPath)
        context.setFillColor(UIColor.black.cgColor)
        context.setBlendMode(.normal)
        //context.drawPath(using: .eoFill)
        
        for caption in captions {
            caption.text.draw(at: caption.position, withAttributes: caption.attributes)
        }
    }
}

// The UIViewRepresentable now manages a container view that holds both
// the camera preview layer and the drawing view on top.
struct CameraPreview: UIViewRepresentable {
    @ObservedObject var cameraManager: AVManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        // Setup the preview layer
        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        // Setup the drawing layer
        let drawingView = DrawingView(frame: view.bounds, videoSize: cameraManager.videoSize, orientation: .leftMirrored)
        print("size: \(cameraManager.videoSize)")
        
        drawingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(drawingView)
        
        // Store the views in the coordinator to update them later
        context.coordinator.previewLayer = previewLayer
        context.coordinator.drawingView = drawingView
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update session if it's newly available
        var orientation: CGImagePropertyOrientation = .leftMirrored
        if context.coordinator.previewLayer?.session == nil, let session = cameraManager.captureSession {
            context.coordinator.previewLayer?.session = session
            
            // FIX: Force previewLayer orientation to match
            if #available(iOS 17.0, *) {
                if let previewConnection = context.coordinator.previewLayer?.connection,
                        previewConnection.isVideoRotationAngleSupported(0) {
                    previewConnection.videoRotationAngle = 0
                    orientation = Utils.Images.cgImageOrientation(fromRotationAngle: 0, mirrored: true)
                }
            } else {
                if let previewConnection = context.coordinator.previewLayer?.connection,
                        previewConnection.isVideoOrientationSupported {
                    previewConnection.videoOrientation = .landscapeLeft
                }
            }
        }
        
        // Update layer frames on size change
        context.coordinator.previewLayer?.frame = uiView.bounds
        context.coordinator.drawingView?.frame = uiView.bounds
        
        // Pass the latest bounding boxes to the drawing view
        // The drawingView will automatically redraw itself when this property is set.
        context.coordinator.drawingView?.orientation = orientation
        context.coordinator.drawingView?.faces = cameraManager.detections
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // Coordinator to hold references to our UIKit views
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
        var drawingView: DrawingView?
    }
}

// The ContentView becomes very clean, as all the complex drawing logic
// is now encapsulated in the CameraPreview representable.
struct ContentView: View {
    @StateObject private var cameraManager = AVManager()
    
    var body: some View {
        CameraPreview(cameraManager: cameraManager)
            .ignoresSafeArea()
            .onAppear(perform: cameraManager.startSession)
            .onDisappear(perform: cameraManager.stopSession)
    }
}

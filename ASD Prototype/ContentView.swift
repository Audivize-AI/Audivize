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
        var frame = frame
        if (frame.width > frame.height) != (videoSize.width > videoSize.height) {
            frame = CGRect(x: frame.origin.y,
                           y: frame.origin.x,
                           width: frame.height,
                           height: frame.width)        
        }
        super.init(frame: frame)
        
        backgroundColor = .clear // Make it transparent
        isOpaque = false
        
        let frameAspectRatio = self.bounds.width / self.bounds.height
        let videoAspectRatio = videoSize.width / videoSize.height
        
        if (videoAspectRatio > frameAspectRatio) {
            // video is too wide -> fix x-axis
            // let drawingWidth = self.bounds.height * videoAspectRatio
            let drawingHeight = self.bounds.width / videoAspectRatio
            self.drawRect = CGRect(
                x: 0,                                           // (self.bounds.width - drawingWidth) / 2,
                y: (self.bounds.height - drawingHeight) / 2,    // 0,
                width: self.bounds.width,                       // drawingWidth,
                height: drawingHeight                           // self.bounds.height
            )
            
            self.scale = .init(
                width: self.bounds.width,
                height: drawingHeight
            )
        } else {
            // video is too tall -> fix y-axis
            // let drawingHeight = self.bounds.width / videoAspectRatio
            let drawingWidth = self.bounds.height * videoAspectRatio
            self.drawRect = CGRect(
                x: (self.bounds.width - drawingWidth) / 2,  // 0,
                y: 0,                                       // (self.bounds.height - drawingHeight) / 2,
                width: drawingWidth,                        // self.bounds.width,
                height: self.bounds.height                  // drawingHeight
            )
            
            self.scale = .init(
                width: drawingWidth,
                height: self.bounds.height
            )
        }
        
        self.videoSize = videoSize
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        context.setLineWidth(3)
        
        struct Caption {
            let text: NSString
            let position: CGPoint
            let attributes: [NSAttributedString.Key: Any]
        }
        
        var captions: [Caption] = []
        
        for face in faces {
            let hue = CGFloat(face.id.hueFromUUID())/360
            let color = UIColor.init(hue: hue, saturation: (hue < 0.56 || hue > 0.83 ? 1 : 0.5), brightness: 1, alpha: 1)
            if face.status == .active {
                context.setStrokeColor(color.cgColor)
                if face.misses > 0 {
                    context.setLineDash(phase: 0, lengths: [5, 5])
                } else {
                    context.setLineDash(phase: 0, lengths: [])
                }
            } else {
                context.setStrokeColor(UIColor.gray.cgColor)
            }
            
            if face.score > ASD.ASDConfiguration.speakingThreshold {
                context.setLineWidth(10)
            } else {
                context.setLineWidth(3)
            }
            let box = face.rect
            // print("\(Date().timeIntervalSince1970 - self.startTime),\(box.midX),\(box.midY),\(box.width * box.height),\(box.width / box.height)")
            // Here, self.bounds is the frame of this view, which is sized to match the preview layer.
            

            let faceRect = CGRect(
                x: drawRect.origin.x + box.minX * scale.width,
                y: drawRect.origin.y + box.minY * scale.height,
                width: box.width * scale.width,
                height: box.height * scale.height
            )
            
            context.stroke(faceRect)
            
            for landmark in face.landmarks {
                let w: CGFloat = 5
                let h: CGFloat = 5
                let pointRect = CGRect(
                    x: drawRect.maxX - landmark.x / CaptureConfiguration.videoWidth * scale.width - w / 2,
                    y: drawRect.maxY - landmark.y / CaptureConfiguration.videoHeight * scale.height - h / 2,
                    width: w,
                    height: h
                )
                context.setFillColor(color.cgColor)
                context.fillEllipse(in: pointRect)
            }
            
            // write the ID above the rectangle
            let idText = face.string as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .regular),
                .foregroundColor: color.cgColor,
                .backgroundColor: UIColor.black.withAlphaComponent(0.5)
            ]

            let textSize = idText.size(withAttributes: attributes)
            let textOrigin = CGPoint(
                x: faceRect.origin.x + (faceRect.width - textSize.width) / 2,
                y: faceRect.origin.y - textSize.height - 20 // small gap above box
            )
            captions.append(.init(text: idText, position: textOrigin, attributes: attributes))
            
        }
        
        context.setBlendMode(.normal)
        
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
        view.layer.addSublayer(cameraManager.previewLayer)
        
        // Setup the drawing layer
        let drawingView = DrawingView(frame: view.bounds, videoSize: CaptureConfiguration.videoSize, orientation: .leftMirrored)
        
        drawingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(drawingView)
        
        // Store the views in the coordinator to update them later
        context.coordinator.previewLayer = cameraManager.previewLayer
        context.coordinator.drawingView = drawingView
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update layer frames on size change
        context.coordinator.previewLayer?.frame = uiView.bounds
        context.coordinator.drawingView?.frame = uiView.bounds
        
        // Pass the latest bounding boxes to the drawing view
        // The drawingView will automatically redraw itself when this property is set.
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

struct ContentView: View {
    @StateObject private var cameraManager = AVManager(cameraAngle: ContentView.getCameraAngle())
    
    var body: some View {
        CameraPreview(cameraManager: cameraManager)
            .ignoresSafeArea()
            .onAppear(perform: cameraManager.startSession)
            .onDisappear(perform: cameraManager.stopSession)
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                    return
                }
                let ifaceOrientation = windowScene.interfaceOrientation
                cameraManager.updateVideoOrientation(for: ifaceOrientation)
            }
    }
    
    private static func getCameraAngle() -> CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return 0.0
        }
        
        switch windowScene.interfaceOrientation {
        case .landscapeRight:
            return 180.0
        case .landscapeLeft:
            return 0.0
        default:
            print("WARNING: Unsupported interface orientation: \(windowScene.interfaceOrientation)")
            return 0.0
        }
    }
}

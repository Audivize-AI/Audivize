import Foundation
import CoreVideo
import CoreGraphics


extension ASD.Tracking {
    final class Detection:
        Identifiable,
        Hashable,
        Equatable
    {
        let id = UUID()
        let rect: CGRect
        let kfRect: CGRect
        let confidence: Float
        let landmarks: [Float]
        
        var embedding: [Float]?
        var isFullFace: Bool = true
        
        init (rect: CGRect, confidence: Float, transformer: CameraCoordinateTransformer, landmarks: [Float]) {
            self.rect = rect
            self.kfRect = transformer.toKfCoordinates(rect)
            self.confidence = confidence
            self.landmarks = landmarks
        }
        
        static func == (lhs: Detection, rhs: Detection) -> Bool {
            return lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
}

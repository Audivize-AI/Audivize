import Foundation
import CoreVideo
import CoreGraphics
import CoreML


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
        
        var buffer: CVPixelBuffer?
        var embedding: [Float]?
        
        init (rect: CGRect, confidence: Float, transformer: CameraCoordinateTransformer) {
            self.rect = rect
            self.kfRect = transformer.toKfCoordinates(rect)
            self.confidence = confidence
        }
        
        static func == (lhs: Detection, rhs: Detection) -> Bool {
            return lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
}

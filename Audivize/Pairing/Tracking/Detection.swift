import Foundation
import CoreVideo
import CoreGraphics


extension Pairing.Tracking {
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
        let attitude: Pairing.Attitude
        
        var embedding: [Float]?
        var isFullFace: Bool = true
        
        init (rect: CGRect, confidence: Float, transformer: CameraCoordinateTransformer, landmarks: [Float]) {
            self.rect = rect
            self.kfRect = transformer.toKfCoordinates(rect)
            self.confidence = confidence
            self.landmarks = landmarks
            self.attitude = Detection.estimateAttitude(for: landmarks)
        }
        
        static func == (lhs: Detection, rhs: Detection) -> Bool {
            return lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        private static func estimateAttitude(for kps: [Float]) -> Pairing.Attitude {
            let leftX = (kps[0] + kps[6]) / 2
            let rightX = (kps[2] + kps[8]) / 2
            let topY = (kps[1] + kps[3]) / 2
            let bottomY = (kps[7] + kps[9]) / 2
            let midX = (leftX + rightX) / 2
            let midY = (topY + bottomY) / 2
            let noseX = kps[4]
            let noseY = kps[5]
            
            let height = topY - bottomY
            let width = rightX - leftX
            
//            guard width < 0 else {
//                return .invalid
//            }
            
            let yaw = atan((noseX - midX) / width)
            
            guard abs(yaw) < yawMax else {
                return .invalid
            }
            
            // expression
            var yRatio = (noseY - midY) / height
            let mouthWidth = hypot(kps[8] - kps[6], kps[9] - kps[7])
            let eyeWidth = hypot(kps[2] - kps[0], kps[3] - kps[1])
            
            let smileThreshold = yRatio > 0 ? smileUpThreshold : smileDownThreshold
            
            if mouthWidth > eyeWidth * smileThreshold {
                yRatio += yRatio > 0 ? smileUpOffset : smileDownOffset
            }
            
            // pitch bin
            let pitch = atan(yRatio)
            
            return .init(pitch: pitch, yaw: yaw)
        }
    }
}

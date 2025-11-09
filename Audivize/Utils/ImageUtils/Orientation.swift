import AVFoundation
import ImageIO

extension Utils.Images {
    @available(iOS 17.0, *)
    static func cgImageOrientation(fromRotationAngle angle: CGFloat,
                            cameraPosition: AVCaptureDevice.Position) -> CGImagePropertyOrientation {
        let rounded = Int(angle) % 360
        switch (rounded, cameraPosition) {
            case (0, .front): return .leftMirrored
            case (90, .front): return .downMirrored
            case (180, .front): return .rightMirrored
            case (270, .front): return .upMirrored
                
            case (0, .back): return .right
            case (90, .back): return .up
            case (180, .back): return .left
            case (270, .back): return .down
                
            default: return .right 
        }
    }
    
    @available(iOS 17.0, *)
    static func cgImageOrientation(fromRotationAngle angle: CGFloat,
                            mirrored: Bool) -> CGImagePropertyOrientation {
        let rounded = Int(angle) % 360
        if mirrored {
            switch rounded {
                case 0: return .leftMirrored
                case 90: return .downMirrored
                case 180: return .rightMirrored
                case 270: return .upMirrored
                default: return .right
            }
        } else {
            switch rounded {
                case 0: return .right
                case 90: return .up
                case 180: return .left
                case 270: return .down
                default: return .right
            }
        }
    }

}

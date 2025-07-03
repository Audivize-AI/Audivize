import CoreML
import Accelerate

extension Utils.ML {
    static func cosineDistance(from a: MLMultiArray, to b: MLMultiArray) -> Float {
        // 1. Quick shape check
        precondition(a.count == b.count)
        precondition(a.dataType == .float32 && b.dataType == .float32)
        
        return a.withUnsafeBufferPointer(ofType: Float.self) { aPtr in
            b.withUnsafeBufferPointer(ofType: Float.self) { bPtr in
                let cosineSimilarity = vDSP.dot(aPtr, bPtr) / sqrt(vDSP.sumOfSquares(aPtr) * vDSP.sumOfSquares(bPtr))
                return 1 - cosineSimilarity
            }
        }
    }
}

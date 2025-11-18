import CoreML
import Accelerate

extension Utils.ML {
    static func cosineDistance(from a: MLMultiArray, to b: MLMultiArray, epsilon: Float = 1e-6) -> Float {
        // 1. Quick shape check
        precondition(a.dataType == .float32 && b.dataType == .float32)
        
        return a.withUnsafeBufferPointer(ofType: Float.self) { aPtr in
            b.withUnsafeBufferPointer(ofType: Float.self) { bPtr in
                return cosineDistance(from: aPtr, to: bPtr)
            }
        }
    }
    
    static func cosineDistance(from a: any AccelerateBuffer<Float>, to b: any AccelerateBuffer<Float>, epsilon: Float = 1e-6) -> Float {
        // Quick shape check
        guard a.count == b.count && a.count > 1 else {
            return .nan
        }
        
        // Compute squared norms and ensure they are nonzero
        let normSquaredA = vDSP.sumOfSquares(a)
        guard normSquaredA > epsilon else {
            return .nan
        }
        let normSquaredB = vDSP.sumOfSquares(b)
        guard normSquaredB > epsilon else {
            return .nan
        }
        
        // Compute cosine similarity
        let normAB = sqrt(normSquaredA * normSquaredB)
        let cosineSimilarity = vDSP.dot(a, b) / normAB
        return 1 - cosineSimilarity
    }
}

import CoreML
import Accelerate

extension Utils.ML {
    static func updateEMA(ema: MLMultiArray, with newArray: MLMultiArray, alpha: Float) {
        precondition(ema.count == newArray.count, "Shape mismatch")
        precondition(ema.dataType == .float32 && newArray.dataType == .float32, "Only Float32 supported")
        
        ema.withUnsafeMutableBufferPointer(ofType: Float.self) { emaPtr, strides in
            newArray.withUnsafeBufferPointer(ofType: Float.self) { newPtr in
                var outPtr = emaPtr
                vDSP.add(
                    emaPtr,
                    vDSP.multiply(alpha, vDSP.subtract(newPtr, emaPtr)),
                    result: &outPtr
                )
            }
        }
    }
}

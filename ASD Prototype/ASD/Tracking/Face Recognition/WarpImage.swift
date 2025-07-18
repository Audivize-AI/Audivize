import Accelerate


extension ASD.Tracking.FaceEmbedder {
    /// Author: Gemini 2.5 Pro
    /// Applies an affine transform to an image
    /// - Parameters:
    ///   - pixelBuffer input pixelBuffer
    ///   - transform the transform being applied
    ///   - size output image size
    /// - Returns a CVPixelBuffer containing the transformed image.
    static func warpImage(_ pixelBuffer: CVPixelBuffer,
                          with transform: CGAffineTransform,
                          size: (width: Int, height: Int) = (Config.imageSize, Config.imageSize)) -> CVPixelBuffer? {
        // 1. Verify the input pixel buffer format is supported by this vImage function.
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard pixelFormat == kCVPixelFormatType_32BGRA || pixelFormat == kCVPixelFormatType_32ARGB else {
            print("Error: Unsupported pixel format \(pixelFormat). Only 32BGRA and 32ARGB are supported.")
            return nil
        }
        
        // 2. Lock the base address of the input buffer for reading.
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            print("Error: Failed to lock input pixel buffer.")
            return nil
        }
        // Ensure the buffer is unlocked even if the function fails.
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        // 3. Create a vImage_Buffer from the input CVPixelBuffer.
        guard let srcBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            print("Error: Could not get base address of input pixel buffer.")
            return nil
        }
        var srcBuffer = vImage_Buffer(
            data: srcBaseAddress,
            height: vImagePixelCount(CVPixelBufferGetHeight(pixelBuffer)),
            width: vImagePixelCount(CVPixelBufferGetWidth(pixelBuffer)),
            rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer)
        )
        
        // 4. Create the destination CVPixelBuffer.
        var dstPixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            size.width,
            size.height,
            pixelFormat, // Use the same pixel format as the input
            attributes as CFDictionary,
            &dstPixelBuffer
        )
        
        guard status == kCVReturnSuccess, let finalPixelBuffer = dstPixelBuffer else {
            print("Error: Failed to create output CVPixelBuffer. Status: \(status)")
            return nil
        }
        
        // 5. Lock the base address of the destination buffer for writing.
        guard CVPixelBufferLockBaseAddress(finalPixelBuffer, []) == kCVReturnSuccess else {
            print("Error: Failed to lock destination pixel buffer.")
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(finalPixelBuffer, []) }
        
        // 6. Create a vImage_Buffer for the destination.
        guard let dstBaseAddress = CVPixelBufferGetBaseAddress(finalPixelBuffer) else {
            print("Error: Could not get base address of destination pixel buffer.")
            return nil
        }
        var dstBuffer = vImage_Buffer(
            data: dstBaseAddress,
            height: vImagePixelCount(CVPixelBufferGetHeight(finalPixelBuffer)),
            width: vImagePixelCount(CVPixelBufferGetWidth(finalPixelBuffer)),
            rowBytes: CVPixelBufferGetBytesPerRow(finalPixelBuffer)
        )
        
        // 7. Convert the CGAffineTransform to the vImage_AffineTransform struct.
        var vImageTransform = vImage_AffineTransform(
            a: Float(transform.a),
            b: Float(transform.b),
            c: Float(transform.c),
            d: Float(transform.d),
            tx: Float(transform.tx),
            ty: Float(transform.ty)
        )
        
        // 8. Perform the affine warp operation.
        // A background color of transparent black is used for pixels outside the source image.
        var backgroundColor: [Pixel_8] = [0, 0, 0, 0]
        let error = vImageAffineWarp_ARGB8888(
            &srcBuffer,
            &dstBuffer,
            nil,
            &vImageTransform,
            &backgroundColor,
            vImage_Flags(kvImageBackgroundColorFill)
        )
        
        guard error == kvImageNoError else {
            print("Error: vImageAffineWarp failed with error code: \(error)")
            return nil
        }
        
        return finalPixelBuffer
    }
}

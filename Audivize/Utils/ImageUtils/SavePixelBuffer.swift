//
//  SaveJPG.swift
//  FaceAlignmentTest
//
//  Created by Benjamin Lee on 7/17/25.
//

import Foundation
import CoreImage
import CoreVideo

extension Utils.Images {
    /// Saves a CVPixelBuffer to a JPEG file.
    /// - Parameters:
    ///   - pixelBuffer: the source buffer
    ///   - url: destination file URL
    ///   - quality: JPEG compression (0.0–1.0)
    static func saveJPEG(from pixelBuffer: CVPixelBuffer,
                         as filename: String,
                         quality: CGFloat = 0.9) throws
    {
        // 1. Lock for safe CPU access (read-only)
        CVPixelBufferLockBaseAddress(pixelBuffer, [.readOnly])
        
        // 2. Wrap buffer in CIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // 3. Create CIContext (reuse for multiple calls if needed)
        let context = CIContext()
        
        // 4. Render JPEG data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let data = context.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        ) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [.readOnly])
            throw NSError(domain: "JPEGError", code: -1, userInfo: nil)
        }
        
        // 5. Unlock buffer
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [.readOnly])
        
        // 6. Make URL
        let fileManager = FileManager.default
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentsURL.appendingPathComponent(filename)
            
            // 7. Write Data
            try data.write(to: fileURL, options: .atomic)
            print("Saved pixel buffer to: \(fileURL)")
        }
    }
}

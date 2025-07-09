//
//  SaveAsGif.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/30/25.
//

import Foundation
import CoreML
import UIKit
import MobileCoreServices


extension Utils.ML {
    /// Saves a 4D MLMultiArray ([1, T, H, W]) as an animated GIF in the app's Documents directory.
    /// - Parameters:
    ///   - array: The MLMultiArray with shape [1, T, H, W] (Float32-compatible).
    ///   - fileName: Name for the GIF file (e.g. "output.gif").
    static func saveMultiArrayAsGIF(_ array: MLMultiArray, fileName: String) {
        // Validate shape
        let shape = array.shape.map { $0.intValue }
        guard shape.count == 4, shape[0] == 1 else {
            print("❌ Expected shape [1, T, H, W], got \(shape)")
            return
        }
        let T = shape[1], H = shape[2], W = shape[3]

        // Prepare frames as UIImage
        var frames: [UIImage] = []
        for t in 0..<T {
            // Extract 2D slice and normalize
            var plane = [Float](repeating: 0, count: H * W)
            var minv = Float.greatestFiniteMagnitude
            var maxv = -Float.greatestFiniteMagnitude
            for y in 0..<H {
                for x in 0..<W {
                    let v = array[[0, t, y, x] as [NSNumber]].floatValue
                    plane[y * W + x] = v
                    minv = min(minv, v)
                    maxv = max(maxv, v)
                }
            }
            let range = (maxv - minv) != 0 ? (maxv - minv) : 1
            let pixels = plane.map { UInt8(clamping: Int((($0 - minv) / range) * 255)) }

            // Create CGImage from grayscale data
            guard let cfData = CFDataCreate(nil, pixels, W * H) else { continue }
            let provider = CGDataProvider(data: cfData)!
            let cgImage = CGImage(
                width: W, height: H,
                bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: W,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent
            )!
            frames.append(UIImage(cgImage: cgImage))
        }

        // Determine output URL in Documents
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let gifURL = docs.appendingPathComponent(fileName)

        // Create GIF
        guard let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, kUTTypeGIF, frames.count, nil) else {
            print("❌ Could not create GIF destination at \(gifURL.path)")
            return
        }

        // Container-level properties (must be set before adding frames)
        let gifProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0  // loop forever
            ]
        ] as CFDictionary
        CGImageDestinationSetProperties(dest, gifProperties)

        // Per-frame properties
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 0.1  // seconds per frame
            ]
        ] as CFDictionary

        // Add frames
        for image in frames {
            guard let cg = image.cgImage else { continue }
            CGImageDestinationAddImage(dest, cg, frameProperties)
        }

        // Finalize
        if CGImageDestinationFinalize(dest) {
            print("✅ GIF saved to: \(gifURL.path)")
        } else {
            print("❌ Failed to write GIF.")
        }
    }
}

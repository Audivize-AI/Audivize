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
import UniformTypeIdentifiers


extension Utils.ML {
    /// Saves a 4D MLMultiArray ([1, T, H, W]) as an animated GIF in the app's Documents directory.
    /// - Parameters:
    ///   - array: The MLMultiArray with shape [1, T, H, W] (Float32-compatible).
    ///   - fileName: Name for the GIF file (e.g. "output.gif").
    static func saveMultiArrayAsGIF(_ array: MLMultiArray, to: String) {
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
            let bias: Float = -2.46504739336
            let scale: Float = 5.92417061611
            for y in 0..<H {
                for x in 0..<W {
                    let v = array[[0, t, y, x] as [NSNumber]].floatValue
                    plane[y * W + x] = v
                }
            }
//            print((minv - bias) / scale, (maxv - bias) / scale)
            let pixels = plane.map {
                UInt8( clamping: Int( ($0 - bias) / scale * 255.0 ) )
            }

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
        let gifURL = docs.appendingPathComponent("Fixed Gifs").appendingPathComponent(to)
        try? FileManager.default.createDirectory(at: gifURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: gifURL)
        
        // Pick the correct type identifier
        let gifUTI: CFString
        if #available(iOS 14.0, *) {
            gifUTI = UTType.gif.identifier as CFString
        } else {
            gifUTI = kUTTypeGIF
        }

        // Frames must be non-empty
        guard frames.isEmpty == false else { print("no frames"); return }

        // Create GIF
        guard let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, gifUTI, frames.count, nil) else {
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
                kCGImagePropertyGIFDelayTime: 1.0 / 25.0  // seconds per frame
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

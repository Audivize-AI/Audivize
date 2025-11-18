//
//  VideoBuffer.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/24/25.
//

import Foundation
import CoreML
import CoreVideo
import CoreGraphics
import Vision
import Accelerate
import DequeModule
import BitCollections

extension Pairing.ASD {
    final class ASDBuffer: Utils.MLBuffer, Hashable, Equatable, @unchecked Sendable {
        struct ASDRequest {
            let callFrame: Int
            let hitHistory: FrameHistory
        }
        
        struct LogitData {
            let callFrame: Int
            let hitHistory: FrameHistory
            let logits: [Float]
        }
        
        private enum ImageProcessingError: Error {
            case lockFailed
            case unsupportedFormat
            case resizeFailed(vImage_Error)
            case grayscaleFailed(vImage_Error)
            case convertFailed(vImage_Error)
        }
        
        public let id: UUID
        
        public var numHits: Int {
            queue.sync { frameHistoryInternal.numHits }
        }
        
        public var isEmpty: Bool {
            queue.sync { frameHistoryInternal.isEmpty }
        }
        
        public var hasEnoughFrames: Bool {
            queue.sync { frameHistoryInternal.hitStreak >= ASDConfiguration.ASDModel.minFrames }
        }
        
        public var isFull: Bool {
            queue.sync { frameHistoryInternal.isFull }
        }
        
        public var frameHistory: FrameHistory {
            queue.sync { frameHistoryInternal }
        }
        
        // (110 / 255 - 0.1688) / 0.4161
        private static let defaultBrightness: Float = 0.09047718613

        private var cropRect: CGRect
        private var newLogits: Deque<LogitData> = []
        private var frameHistoryInternal: FrameHistory
        
        // MARK: - init
        
        init() {
            self.id = UUID()
            self.cropRect = .zero
            let frameSize = ASDConfiguration.frameSize
            self.frameHistoryInternal = .init()
            super.init(
                chunkShape: [Int(frameSize.width), Int(frameSize.height)],
                defaultChunk: .init(repeating: Self.defaultBrightness, count: Int(frameSize.width * frameSize.height)),
                length: ASDConfiguration.ASDModel.videoLength,
                frontPadding: ASDConfiguration.videoBufferFrontPadding,
                backPadding: ASDConfiguration.videoBufferBackPadding
            )
        }
        
        // MARK: - public methods
        
        /// Reactivate the ASDVideo
        public func activate() {
            queue.sync(flags: .barrier) {
                // Wipe logits
                self.newLogits.removeAll(keepingCapacity: true)
                
                // wipe the entire buffer
                if !self.frameHistoryInternal.isEmpty {
                    self.withUnsafeMutableBufferPointer { p in
                        var pattern = Self.defaultBrightness.bitPattern
                        memset_pattern4(p.baseAddress!, &pattern, self.count * MemoryLayout<Float>.stride)
                    }
                    self.frameHistoryInternal.reset()
                }
            }
        }
        
        /// Write a frame to the buffer
        /// - Parameters:
        ///   - pixelBuffer: The full frame
        ///   - rect: The portion of the frame containining the face
        ///   - drop: Whether to drop the frame
        ///   - isMiss: Whether to the track was missed that frame
        public func writeFrame(from pixelBuffer: CVPixelBuffer, croppedTo rect: CGRect, isMiss: Bool = false, drop: Bool = false) throws {
            
            guard rect != .infinite,
                  rect.width.isNaN == false, rect.height.isNaN == false,
                  rect.width != 0 && rect.height != 0 else {
                return
            }
            
            queue.sync(flags: .barrier) {
                self.updateCropRect(pixelBuffer: pixelBuffer, rect: rect)
            }
            
            // handle skipped frames
            guard !drop else { return }
            
            // write new frame
            try self.withUnsafeWritingPointer {
                try Self.preprocessImage(pixelBuffer: pixelBuffer,
                                         cropTo: cropRect,
                                         resizeTo: ASDConfiguration.frameSize,
                                         to: $0.baseAddress!)
            }
            
            queue.sync(flags: .barrier) {
                if !isMiss {
                    frameHistoryInternal.registerHit()
                } else {
                    frameHistoryInternal.registerMiss()
                }
            }
        }
        
        /// Skip a frame by adding a blank frame to the buffer
        /// - Parameters:
        ///   - drop: Whether to drop the frame
        public func skipFrame(drop: Bool = false) {
            queue.sync {
                // do nothing if it's already empty
                guard self.frameHistoryInternal.isEmpty == false else { return }
            }
            
            // handle skipped frames
            guard !drop else { return }
            
            // write blank frame
            self.withUnsafeWritingPointer { p in
                var pattern = Self.defaultBrightness.bitPattern
                memset_pattern4(p.baseAddress!, &pattern, self.chunkSize * MemoryLayout<Float>.stride)
            }
            
            queue.sync(flags: .barrier) {
                frameHistoryInternal.registerMiss()
            }
        }
        
        /// Pops the next batch of new logits
        /// - Returns: The new next batch of new logits
        public func popNewLogits() -> LogitData? {
            queue.sync(flags: .barrier) {
                return newLogits.popFirst()
            }
        }
        
        /// Add new logits
        /// - Parameters:
        ///   - startIndex: Frame index of the first valid logit
        ///   - endIndex: Frame index of the last valid logit
        ///   - logits: New logits to add
        public func addNewLogits(from request: ASDRequest, logits: [Float]) {
            queue.sync(flags: .barrier) {
                newLogits.append(LogitData(callFrame: request.callFrame,
                                           hitHistory: request.hitHistory,
                                           logits: logits))
            }
        }
        
        /// Make an ASD Request
        /// - Returns: An object containing the ASD request data
        public func makeASDRequest(atFrame frameIndex: Int) -> ASDRequest {
            return .init(callFrame: frameIndex, hitHistory: frameHistory)
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        public static func == (lhs: ASDBuffer, rhs: ASDBuffer) -> Bool {
            return lhs.id == rhs.id
        }
        
        // MARK: - private helpers
        
        @inline(__always)
        private func updateCropRect(pixelBuffer: CVPixelBuffer, rect detectionRect: CGRect) {
            let bufferWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            let bufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
            // Get detection box dimensions and center in pixels.
            let detectionWidth = detectionRect.width * bufferWidth
            let detectionHeight = detectionRect.height * bufferHeight
            let detectionCenterX = detectionRect.midX * bufferWidth
            let detectionCenterY = detectionRect.midY * bufferHeight

            let bs = max(detectionWidth, detectionHeight) / 2.0 // box size
            let cs = ASDConfiguration.cropScale
            
            let finalSideLength = bs * (1.0 + cs)
            let finalHalfSide = finalSideLength / 2.0
            
            let intermediateCropCenterX = detectionCenterX
            let intermediateCropCenterY = detectionCenterY + (bs * cs)
            
            let finalOriginX = intermediateCropCenterX - finalHalfSide
            let finalOriginY = intermediateCropCenterY - finalHalfSide
            
            self.cropRect = CGRect(
                x: finalOriginX,
                y: finalOriginY,
                width: finalSideLength,
                height: finalSideLength
            )
        }
        
        /// Preprocess image for the ASD Model.
        ///
        /// - Parameters:
        ///   - cropRect: The `CGRect` defining the region to crop. Out-of-bounds areas are padded.
        ///   - targetSize: The final `CGSize` for the output data (e.g., 224x224).
        ///   - outputPointer: An `UnsafeMutablePointer<Float32>` to which the final, flattened
        ///                  grayscale data will be written. The pointer must point to a memory
        ///                  region large enough to hold `targetSize.width * targetSize.height` floats.
        /// - Throws: An `ImageProcessingError` if any step in the vImage pipeline fails.
        private static func preprocessImage(
            pixelBuffer: CVPixelBuffer,
            cropTo cropRect: CGRect,
            resizeTo targetSize: CGSize,
            to outputBuffer: UnsafeMutablePointer<Float>
        ) throws {
            // 1) Validate format & lock
            guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
                throw ImageProcessingError.unsupportedFormat
            }
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                throw ImageProcessingError.lockFailed
            }
            
            // 2) Compute source & crop geometry
            let srcW       = CVPixelBufferGetWidth(pixelBuffer)
            let srcH       = CVPixelBufferGetHeight(pixelBuffer)
            let srcStride  = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let cropX      = Int(cropRect.origin.x)
            let cropY      = Int(cropRect.origin.y)
            let cropW      = Int(cropRect.width)
            let cropH      = Int(cropRect.height)
            let cropStride = cropW * 4
            
            // 3) Allocate & fill cropBuffer with pad color A=255, R=110, G=110, B=110
            let cropData = UnsafeMutableRawPointer.allocate(byteCount: cropH * cropStride,
                                                            alignment: 64)
            defer { cropData.deallocate() }
            var cropBuffer = vImage_Buffer(data:       cropData,
                                           height:     vImagePixelCount(cropH),
                                           width:      vImagePixelCount(cropW),
                                           rowBytes:   cropStride)
            
            // Pad color in BGRA memory layout → we’ll permute later anyway
            var padColor: UInt32 = 0xFF6E6E6E
            let fillErr = vImageBufferFill_ARGB8888(&cropBuffer,
                                                    &padColor,
                                                    vImage_Flags(kvImageNoFlags))
            guard fillErr == kvImageNoError else {
                throw ImageProcessingError.resizeFailed(fillErr)
            }
            
            // 4) Copy overlapping region from source into the right offset inside cropBuffer
            let xSrcStart = max(0, cropX)
            let ySrcStart = max(0, cropY)
            let xSrcEnd   = min(srcW, cropX + cropW)
            let ySrcEnd   = min(srcH, cropY + cropH)
            
            if xSrcEnd > xSrcStart && ySrcEnd > ySrcStart {
                let copyW = (xSrcEnd - xSrcStart) * 4
                let copyH = ySrcEnd - ySrcStart
                let destX = (xSrcStart - cropX) * 4
                let destY =  ySrcStart - cropY
                
                for row in 0..<copyH {
                    let srcRowPtr = baseAddress.advanced(
                        by: (ySrcStart + row) * srcStride + xSrcStart * 4
                    )
                    let dstRowPtr = cropData.advanced(
                        by: (destY + row) * cropStride + destX
                    )
                    memcpy(dstRowPtr, srcRowPtr, copyW)
                }
            }
            
            // 5) Now scale the padded cropBuffer → scaledBuffer
            let destW      = Int(targetSize.width)
            let destH      = Int(targetSize.height)
            let destStride = destW * 4
            let scaledData = UnsafeMutableRawPointer.allocate(byteCount: destH * destStride,
                                                              alignment: 64)
            defer { scaledData.deallocate() }
            var scaledBuffer = vImage_Buffer(data:     scaledData,
                                             height:   vImagePixelCount(destH),
                                             width:    vImagePixelCount(destW),
                                             rowBytes: destStride)
            var err = vImageScale_ARGB8888(&cropBuffer,
                                           &scaledBuffer,
                                           nil,
                                           vImage_Flags(kvImageHighQualityResampling))
            guard err == kvImageNoError else {
                throw ImageProcessingError.resizeFailed(err)
            }
            
            // 6) Permute BGRA→ARGB for the luma matrix multiply
            let permuteMap: [UInt8] = [3, 2, 1, 0]
            let permData = UnsafeMutableRawPointer.allocate(byteCount: destH * destStride,
                                                            alignment: 64)
            defer { permData.deallocate() }
            var permBuffer = vImage_Buffer(data:     permData,
                                           height:   vImagePixelCount(destH),
                                           width:    vImagePixelCount(destW),
                                           rowBytes: destStride)
            err = vImagePermuteChannels_ARGB8888(&scaledBuffer,
                                                 &permBuffer,
                                                 permuteMap,
                                                 vImage_Flags(kvImageNoFlags))
            guard err == kvImageNoError else {
                throw ImageProcessingError.resizeFailed(err)
            }
            
            // 7) Convert ARGB8888 → 8-bit luma
            let gray8Stride = destW
            let gray8Data = UnsafeMutableRawPointer.allocate(byteCount: destH * gray8Stride,
                                                             alignment: 1)
            defer { gray8Data.deallocate() }
            var gray8Buffer = vImage_Buffer(data:     gray8Data,
                                            height:   vImagePixelCount(destH),
                                            width:    vImagePixelCount(destW),
                                            rowBytes: gray8Stride)
            
            let divisor: Int32 = 0x1000
            let rCoef = Int16(0.299 * Float(divisor))
            let gCoef = Int16(0.587 * Float(divisor))
            let bCoef = Int16(0.114 * Float(divisor))
            var matrix: [Int16] = [ 0, rCoef, gCoef, bCoef ]
            var preBias = [Int16](repeating: 0, count: 4)
            let postBias: Int32 = 0
            
            err = vImageMatrixMultiply_ARGB8888ToPlanar8(&permBuffer,
                                                         &gray8Buffer,
                                                         &matrix,
                                                         divisor,
                                                         &preBias,
                                                         postBias,
                                                         vImage_Flags(kvImageNoFlags))
            guard err == kvImageNoError else {
                throw ImageProcessingError.grayscaleFailed(err)
            }
            
            // 8) Convert Planar8 → PlanarF (Float32) into user’s outputBuffer
            let outStride = destW * MemoryLayout<Float>.stride
            var grayFBuffer = vImage_Buffer(data:     outputBuffer,
                                            height:   vImagePixelCount(destH),
                                            width:    vImagePixelCount(destW),
                                            rowBytes: outStride)
            err = vImageConvert_Planar8toPlanarF(&gray8Buffer,
                                                 &grayFBuffer,
                                                 5.92417061611,  // scale
                                                 -2.46504739336, // bias
                                                 vImage_Flags(kvImageNoFlags))
            guard err == kvImageNoError else {
                throw ImageProcessingError.convertFailed(err)
            }
        }
    }
}

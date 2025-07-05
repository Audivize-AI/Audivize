//
//  KFCoordinateTransform.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/4/25.
//

import Foundation

extension ASD.Tracking {
    enum CameraOrientation: Int {
        case base0      = 0
        case base90     = 1
        case base180    = 2
        case base270    = 3
        case mirror0    = 4
        case mirror90   = 5
        case mirror180  = 6
        case mirror270  = 7
        
        public var isMirrored: Bool {
            return self.rawValue >= 4
        }
        
        init(angle: CGFloat, mirrored: Bool) {
            self.init(rawValue: Int(angle.rounded()) / 90 + (mirrored ? 4 : 0))!
        }
    }

    class CameraCoordinateTransformer {
        public var orientation: CameraOrientation
        public let width: CGFloat
        public let height: CGFloat
        
        private let reciprocalWidth: CGFloat
        private let reciprocalHeight: CGFloat
        
        init(orientation: CameraOrientation, width: CGFloat, height: CGFloat) {
            self.orientation = orientation
            self.width = width
            self.height = height
            self.reciprocalWidth = 1.0 / width
            self.reciprocalHeight = 1.0 / height
        }
        
        public func toKfCoordinates(_ rect: CGRect) -> CGRect {
            switch orientation {
            case .base0:
                return CGRect(
                    x: self.width * (rect.minX - 0.5),
                    y: self.height * (rect.minY - 0.5),
                    width: self.width * rect.width,
                    height: self.height * rect.height
                )
            case .mirror0:
                return CGRect(
                    x: self.width * (0.5 - rect.maxX),
                    y: self.height * (rect.minY - 0.5),
                    width: self.width * rect.width,
                    height: self.height * rect.height
                )
            case .base90:
                return CGRect(
                    x: self.width * (0.5 - rect.maxY),
                    y: self.height * (rect.minX - 0.5),
                    width: self.width * rect.height,
                    height: self.height * rect.width
                )
            case .mirror90:
                return CGRect(
                    x: self.width * (rect.minY - 0.5),
                    y: self.height * (rect.minX - 0.5),
                    width: self.width * rect.height,
                    height: self.height * rect.width
                )
            case .base180:
                return CGRect(
                    x: self.width * (0.5 - rect.maxX),
                    y: self.height * (0.5 - rect.maxY),
                    width: self.width * rect.width,
                    height: self.height * rect.height
                )
            case .mirror180:
                return CGRect(
                    x: self.width * (rect.minX - 0.5),
                    y: self.height * (0.5 - rect.maxY),
                    width: self.width * rect.width,
                    height: self.height * rect.height
                )
            case .base270:
                return CGRect(
                    x: self.width * (rect.minY - 0.5),
                    y: self.height * (0.5 - rect.maxX),
                    width: self.width * rect.height,
                    height: self.height * rect.width
                )
            case .mirror270:
                return CGRect(
                    x: self.width * (0.5 - rect.maxY),
                    y: self.height * (0.5 - rect.maxX),
                    width: self.width * rect.height,
                    height: self.height * rect.width
                )
            }
        }
        
        public func toTrackCoordinates(_ rect: CGRect) -> CGRect {
            switch orientation {
            case .base0:
                return CGRect(
                    x: reciprocalWidth * rect.minX + 0.5,
                    y: reciprocalHeight * rect.minY + 0.5,
                    width: reciprocalWidth * rect.width,
                    height: reciprocalHeight * rect.height
                )
            case .mirror0:
                return CGRect(
                    x: reciprocalWidth * -rect.maxX + 0.5,
                    y: reciprocalHeight * rect.minY + 0.5,
                    width: reciprocalWidth * rect.width,
                    height: reciprocalHeight * rect.height
                )
            case .base270:
                return CGRect(
                    x: reciprocalWidth * -rect.maxY + 0.5,
                    y: reciprocalHeight * rect.minX + 0.5,
                    width: reciprocalWidth * rect.height,
                    height: reciprocalHeight * rect.width
                )
            case .mirror270:
                return CGRect(
                    x: reciprocalWidth * rect.minY + 0.5,
                    y: reciprocalHeight * rect.minX + 0.5,
                    width: reciprocalWidth * rect.height,
                    height: reciprocalHeight * rect.width
                )
            case .base180:
                return CGRect(
                    x: reciprocalWidth * -rect.maxX + 0.5,
                    y: reciprocalHeight * -rect.maxY + 0.5,
                    width: reciprocalWidth * rect.width,
                    height: reciprocalHeight * rect.height
                )
            case .mirror180:
                return CGRect(
                    x: reciprocalWidth * rect.minX + 0.5,
                    y: reciprocalHeight * -rect.maxY + 0.5,
                    width: reciprocalWidth * rect.width,
                    height: reciprocalHeight * rect.height
                )
            case .base90:
                return CGRect(
                    x: reciprocalWidth * rect.minY + 0.5,
                    y: reciprocalHeight * -rect.maxX + 0.5,
                    width: reciprocalWidth * rect.height,
                    height: reciprocalHeight * rect.width
                )
            case .mirror90:
                return CGRect(
                    x: reciprocalWidth * -rect.maxY + 0.5,
                    y: reciprocalHeight * -rect.maxX + 0.5,
                    width: reciprocalWidth * rect.height,
                    height: reciprocalHeight * rect.width
                )
            }
        }
    }
}


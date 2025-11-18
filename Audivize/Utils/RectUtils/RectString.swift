//
//  ToString.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/6/25.
//

import Foundation
import CoreGraphics


extension CGRect {
    var string: String {
        return "Rect[(\(minX), \(minY)), (\(width), \(height))]"
    }
}

//
//  IoU.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/21/25.
//

import Foundation
import CoreGraphics

extension Utils {
    static func iou(_ box1: CGRect, _ box2: CGRect) -> Float {
        let intersectionWidth = min(box1.maxX, box2.maxX) - max(box1.minX, box2.minX)
        let intersectionHeight = min(box1.maxY, box2.maxY) - max(box1.minY, box2.minY)
        
        if intersectionWidth <= 0 || intersectionHeight <= 0 {
            return 0
        }
        
        let area1 = box1.width * box1.height
        let area2 = box2.width * box2.height
        let areaIntersection = intersectionWidth * intersectionHeight
        let areaUnion = area1 + area2 - areaIntersection
        
        return Float(areaIntersection / areaUnion)
    }
}

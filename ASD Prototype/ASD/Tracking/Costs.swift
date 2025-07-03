//
//  Costs.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/24/25.
//

import Foundation

extension ASD.Tracking {
    final class Costs {
        var iou: Float
        var ocm: Float
        var confidence: Float
        var appearance: Float
        var total: Float
        
        var hasConfidence: Bool { self.confidence != Float.infinity }
        var hasAppearance: Bool { self.appearance != Float.infinity }
        var hasIoU: Bool { self.iou != Float.infinity }
        var hasOCM: Bool { self.ocm != Float.infinity }
        var hasTotal: Bool { self.total != Float.infinity }
        
        var string : String {
            let totalString: String = self.hasTotal ? "Cost = \(self.total)" : "Cost:"
            let iouString: String = self.hasIoU ? "\n\tIoU: \(self.iou)" : "\n"
            let ocmString: String = self.hasOCM ? "\n\tOCM: \(self.ocm)" : "\n"
            let confidenceString: String = self.hasConfidence ? "\n\tConfidence: \(self.confidence)" : "\n"
            let appearanceString: String = self.hasAppearance ? "\n\tAppearance: \(self.appearance)" : "\n"
            return "\(totalString)\(iouString)\(appearanceString)\(confidenceString)\(ocmString)"
        }
        
        init(iou: Float = .infinity,
             confidence: Float = .infinity,
             ocm: Float = .infinity,
             appearance: Float = .infinity,
             total: Float = .infinity)
        {
            self.iou = iou
            self.confidence = confidence
            self.ocm = ocm
            self.appearance = appearance
            self.total = total
        }
    }
}

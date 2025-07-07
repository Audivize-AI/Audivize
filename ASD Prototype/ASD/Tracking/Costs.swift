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
        var total: Float {
            -self.iou                                                 +
             self.appearance * TrackingConfiguration.appearanceWeight +
             self.ocm        * TrackingConfiguration.ocmWeight        +
             self.confidence * TrackingConfiguration.confidenceWeight
        }
        
        var hasConfidence: Bool { self.confidence != 0 }
        var hasAppearance: Bool { self.appearance != 0 }
        var hasIoU: Bool { self.iou != 0 }
        var hasOCM: Bool { self.ocm != 0 }
        var hasTotal: Bool { self.total != 0 }
        
        var string : String {
//            let totalString: String = self.hasTotal ? "Cost = \(self.total)" : "Cost:"
//            let iouString: String = self.hasIoU ? "\n\tIoU: \(self.iou)" : "\n"
//            let ocmString: String = self.hasOCM ? "\n\tOCM: \(self.ocm)" : "\n"
//            let confidenceString: String = self.hasConfidence ? "\n\tConfidence: \(self.confidence)" : "\n"
            let appearanceString: String = self.hasAppearance ? String(format: "\n\tAppearance: %.2f", 10 * self.appearance) : "\n"
            return appearanceString //"\(totalString)\(iouString)\(appearanceString)\(confidenceString)\(ocmString)"
        }
        
        public init(iou: Float = 0,
             confidence: Float = 0,
             ocm: Float = 0,
             appearance: Float = 0)
        {
            self.iou = iou
            self.ocm = ocm
            self.confidence = confidence
            self.appearance = appearance
        }
    }
}

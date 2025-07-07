//
//  PrintMultiArray.swift
//  ASD Prototype
//
//  Created by Benjamin Lee on 7/6/25.
//

import Foundation
public import CoreML

public extension MLMultiArray {
    var stringValue: String {
        var output = "["
        self.withUnsafeBufferPointer(ofType: Float.self) { ptr in
            output += ptr.map(\.self).map(\.description).joined(separator: ", ")
        }
        output += "]"
        return output
    }
}

extension Utils.ML {
    static func printMultiArray(_ multiArray: MLMultiArray) {
        print(multiArray.stringValue)
    }
}

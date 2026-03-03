//
//  TextDisplay.swift
//  audi2
//
//  Created by Sebastian Zimmerman on 3/2/26.
//

import SwiftUI
import Foundation

extension Double {
    func removeZerosFromEnd() -> String {
        let formatter = NumberFormatter()
        let number = NSNumber(value: self)
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 16 // maximum digits in Double after the dot (maximum precision)
        return String(formatter.string(from: number) ?? "")
    }
}
struct TextDisplay: View {
    @State var textSize: Double
    @State private var isEditing = false
    var body: some View {
        
        VStack {
            Slider (
                value: $textSize,
                in: 0...100,
                step: 1,
                onEditingChanged: { editing in
                    isEditing = editing
                }
            )
        }
    }
}


#Preview {
    TextDisplay(textSize: 1.0)
}


//
//  ButtonStyles.swift
//  audi2
//
//  Created by Sebastian Zimmerman on 2/26/26.
//
import SwiftUI

struct SocialButtonStyle: ButtonStyle {
    let width: CGFloat
    let height: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: width, height: height)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(0)
            .scaleEffect(configuration.isPressed ? 0.97: 1)
    }
}

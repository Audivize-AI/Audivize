//
//  BigPageView.swift
//  1
//
//  Created by N.B.K. on 2/1/26.
//

import SwiftUI

struct BigPageView: View {
    let title: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            Text(title)
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
        .navigationTitle(title)
    }
}



//
//  HomeView.swift
//  AudivizeUI2
//
//  Created by N.B.K. on 2/1/26.
//

import SwiftUI

struct HomeView: View {
    @Binding var selection: SidebarItem?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Background
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            // Main title
            Text("Home")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            // Bottom oval navigation
            VStack {
                Spacer()
                HStack(spacing: 20) {
                    bottomButton(item: .home)
                    bottomButton(item: .camera)
                    bottomButton(item: .profile)
                    bottomButton(item: .settings)
                }
                .padding(.vertical, 8)      // less height
                .padding(.horizontal, 20)   // side padding
                .background(
                    RoundedRectangle(cornerRadius: 25)  // slightly smaller corner
                        .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                )
                .padding(.bottom, 20)  // less bottom spacing
            }
        }
        .navigationTitle("Home")
    }

    // Bottom button
    @ViewBuilder
    func bottomButton(item: SidebarItem) -> some View {
        Button {
            selection = item
        } label: {
            VStack(spacing: 2) {  // smaller spacing
                Image(systemName: item.icon)
                    .font(.title3)  // smaller icon
                    .foregroundColor(selection == item ? .blue : (colorScheme == .dark ? .white : .black))
                Text(item.rawValue)
                    .font(.caption2) // smaller text
                    .foregroundColor(selection == item ? .blue : (colorScheme == .dark ? .white : .black))
            }
            .frame(width: 50, height: 40) // smaller button
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    HomeView(selection: .constant(.home))
}


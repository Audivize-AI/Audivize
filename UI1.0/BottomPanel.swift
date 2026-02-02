//
//  BottomPanel.swift
//  AudivizeUI2
//
//  Created by N.B.K. on 2/1/26.
//

import SwiftUI

struct BottomPanel: View {
    @Binding var selection: SidebarItem?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 20) {
            panelButton(item: .home)
            panelButton(item: .camera)
            panelButton(item: .profile)
            panelButton(item: .settings)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
        )
        .padding(.bottom, 20)
    }

    @ViewBuilder
    func panelButton(item: SidebarItem) -> some View {
        Button {
            selection = item
        } label: {
            VStack(spacing: 2) {
                Image(systemName: item.icon)
                    .font(.title3)
                    .foregroundColor(selection == item ? .blue : (colorScheme == .dark ? .white : .black))
                Text(item.rawValue)
                    .font(.caption2)
                    .foregroundColor(selection == item ? .blue : (colorScheme == .dark ? .white : .black))
            }
            .frame(width: 50, height: 40)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    BottomPanel(selection: .constant(.home))
        .previewLayout(.sizeThatFits)
}

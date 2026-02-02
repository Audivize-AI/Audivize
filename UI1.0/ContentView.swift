//
//  ContentView.swift
//  1
//
//  Created by N.B.K. and Sebastian Zimmerman on 2/1/26.
//

import SwiftUI

// MARK: - App Theme
enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark
}

// MARK: - Sidebar Items
enum SidebarItem: String, Identifiable {
    case home = "Home"
    case camera = "Camera"
    case profile = "Profile"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .camera: return "camera"
        case .profile: return "person"
        case .settings: return "gear"
        }
    }

    // Menu order
    static let menuOrder: [SidebarItem] = [
        .home,
        .camera,
        .profile,
        .settings
    ]
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .home
    @AppStorage("appTheme") private var appTheme: String = AppTheme.system.rawValue

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.menuOrder, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationTitle("Menu")
        } detail: {
            NavigationStack {
                ZStack {
                    // Main content
                    Group {
                        switch selection {
                        case .home:
                            BigPageView(title: "Home")
                        case .camera:
                            CameraView()
                        case .profile:
                            BigPageView(title: "Profile")
                        case .settings:
                            SettingsView(appTheme: $appTheme)
                        default:
                            BigPageView(title: "Home")
                        }
                    }

                    // Overlay bottom panel only on certain pages
                    VStack {
                        Spacer()
                        BottomPanel(selection: $selection)
                    }
                }
            }
        }
        .preferredColorScheme(selectedColorScheme)
    }

    var selectedColorScheme: ColorScheme? {
        switch AppTheme(rawValue: appTheme) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}


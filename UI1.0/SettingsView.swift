//
//  SettingsView.swift
//  1
//
//  Created by N.B.K. on 2/1/26.
//


import SwiftUI

struct SettingsView: View {
    @Binding var appTheme: String

    var body: some View {
        Form {
            Section(header: Text("Appearance")) {
                Picker("Theme", selection: $appTheme) {
                    Text("System").tag(AppTheme.system.rawValue)
                    Text("Light").tag(AppTheme.light.rawValue)
                    Text("Dark").tag(AppTheme.dark.rawValue)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }
        .navigationTitle("Settings")
    }
}


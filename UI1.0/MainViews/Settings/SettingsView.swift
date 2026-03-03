//
//  SettingsView.swift
//  1
//
//  Created by N.B.K. and Sebastian Zimmerman on 2/1/26.
//


import SwiftUI
struct dropDownOption: Identifiable {
    var id: UUID = UUID()
    var title: String
    var color: Color
    var icon: String? = nil
    var action: () -> Void
}
enum dropDownAlignment {
   case leading
   case center
   case trailing
}
struct SettingsView: View {
    @Binding var appTheme: String
    // Currently only has app theme color changer
    var body: some View {
        VStack {
            NavigationStack {
                Form {
                    Section(header: Text("Text Display")) {
                        NavigationLink("Text Display") {
                        }
                    }
                    // App theme color changer
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
    }
}


#Preview {
    @AppStorage("appTheme") var appTheme: String = AppTheme.system.rawValue

    SettingsView(appTheme: $appTheme)
}

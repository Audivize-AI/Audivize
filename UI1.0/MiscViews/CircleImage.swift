//
//  CircleImage.swift
//  audi2
//
//  Created by Sebastian Zimmerman on 2/19/26.
//

import SwiftUI
import PhotosUI
struct CircleImage: View {
    var imageName: String
    @State var selectedItem: PhotosPickerItem? = nil
    @State var profileImage: Image = Image("image")
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        
        PhotosPicker(selection: $selectedItem, matching: .images) {
            // CircleImage view for circular image
            ZStack {
                profileImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaledToFill()
                    .frame(width: 150, height: 150)
                    .clipShape(Circle())
                    
                // Pencil image in order to inform the user this image can be changed
                Image(systemName: "pencil")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .offset(x: 30, y: 65)
                    .rotationEffect(.degrees(-20))
            }
        }
        .onChange(of: selectedItem ?? nil) {_, newItem in
            Task {
                // Image selector for profile view embedded into CircleImage view
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                    let uiImage = UIImage(data: data) {
                    profileImage = Image(uiImage: uiImage)
                }
                    
            }
        }
        
            
        
    }
}
#Preview {
    CircleImage(imageName: "image")
}

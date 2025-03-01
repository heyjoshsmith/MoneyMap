//
//  MyPhotoPicker.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/28/25.
//

import SwiftUI
import PhotosUI

struct MyPhotoPicker: View {
    
    @Binding var selection: PhotosPickerItem?
    let onSelection: (ImageType) -> Void
    
    @State private var savedFiles = 0
    
    var body: some View {
        VStack(spacing: 10) {
            PhotoButton("Image Playground", systemImage: "apple.image.playground", color: .pink) {
                onSelection(.imagePlayground)
            }
            
            PhotosPicker(selection: $selection, matching: .images) {
                PhotoButton("Photos", systemImage: "photo.on.rectangle.angled", color: .blue)
            }
            
            PhotoButton("Saved Images", systemImage: "photo.badge.checkmark", color: .green, value: $savedFiles) {
                onSelection(.savedImages)
            }
            
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            savedFiles = getSavedFiles().count
        }
    }
}

enum ImageType: String, CaseIterable, Identifiable {
    case imagePlayground, photos, savedImages
    
    var name: String {
        switch self {
        case .imagePlayground:
            return "Image Playground"
        case .photos:
            return "Photos"
        case .savedImages:
            return "Saved Images"
        }
    }
    
    var id: Self { return self }
}

private struct PhotoButton: View {
    
    init(_ title: String, systemImage: String, color: Color, value: Binding<Int>? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.value = value
        self.action = action
    }
    
    var title: String
    var systemImage: String
    var color: Color
    var value: Binding<Int>?  // Optional binding
    var action: (() -> Void)?
    
    var body: some View {
        if let action {
            Button(action: action) {
                label
            }
            .disabled(value?.wrappedValue == 0)
            .opacity(value?.wrappedValue == 0 ? 0.5 : 1)
        } else {
            label
        }
    }
    
    var label: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 40, alignment: .center)
            Text(title)
                .foregroundStyle(Color.primary)
            if let value = value?.wrappedValue {
                Spacer()
                Text("\(value) Image\(value == 1 ? "" : "s")")
                    .foregroundStyle(Color.secondary)
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .imageScale(.large)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }
}

#Preview {
    MyPhotoPicker(selection: .constant(nil)) { imageType in
        
    }
}

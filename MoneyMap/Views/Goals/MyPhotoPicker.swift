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
    
    var body: some View {
        VStack(spacing: MoneyMapDesign.compactSpacing) {
            PhotoButton("Image Playground", detail: "Generate art for this goal.", systemImage: "apple.image.playground", color: .pink) {
                onSelection(.imagePlayground)
            }
            
            PhotosPicker(selection: $selection, matching: .images) {
                PhotoButton("Photos", detail: "Choose from your photo library.", systemImage: "photo.on.rectangle.angled", color: .blue)
            }
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MoneyMapDesign.groupedBackground)
    }
}

enum ImageType: String, CaseIterable, Identifiable {
    case imagePlayground, photos
    
    var name: String {
        switch self {
        case .imagePlayground:
            return "Image Playground"
        case .photos:
            return "Photos"
        }
    }
    
    var id: Self { return self }
}

private struct PhotoButton: View {
    
    init(_ title: String, detail: String, systemImage: String, color: Color, value: Binding<Int>? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.color = color
        self.value = value
        self.action = action
    }
    
    var title: String
    var detail: String
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
                .frame(width: 30, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
        .background(MoneyMapDesign.surfaceBackground)
        .clipShape(.rect(cornerRadius: MoneyMapDesign.controlCornerRadius))
    }
}

#Preview {
    MyPhotoPicker(selection: .constant(nil)) { imageType in
        
    }
}

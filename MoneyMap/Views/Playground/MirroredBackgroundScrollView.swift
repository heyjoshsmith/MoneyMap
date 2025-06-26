//
//  SwiftUIView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI
//import Glur

struct MirroredBackgroundScrollView<Content: View>: View {
    
    let image: Image?
    let content: () -> Content
    
    init(_ image: UIImage? = nil, @ViewBuilder content: @escaping () -> Content) {
        if let image {
            self.image = Image(uiImage: image)
        } else {
            self.image = nil
        }
        self.content = content
    }
    
    var body: some View {
        if let image {
            GeometryReader { proxy in
                ScrollView {
                    ZStack(alignment: .top) {
                        
                        mirroredBackground(image)
                            .offset(y: proxy.frame(in: .global).minY)
                            .edgesIgnoringSafeArea(.all)

                        
                        // Foreground content
                        content()
                            .padding(.top, proxy.size.width)
                        
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)
        } else {
            GeometryReader { proxy in
                ScrollView {
                    content()
                }
            }
        }
    }
    
    // Background View with Mirrored Reflection
    private func mirroredBackground(_ image: Image) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<10, id: \.self) { index in
                image
                    .resizable()
                    .scaledToFit()
                    .clipped()
                    .scaleEffect(y: index % 2 == 0 ? 1 : -1)
                    .blur(radius: index == 0 ? 0 : 20, opaque: true)
//                    .glur(radius: index == 0 ? 20 : 0)
            }
        }
    }
}

#Preview {
    MirroredBackgroundScrollView() {
        Text("hi")
            .padding()
    }
}

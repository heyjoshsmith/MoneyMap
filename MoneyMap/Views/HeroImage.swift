//
//  HeroImage.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI
import Glur

struct HeroImage: View {
    
    init(_ label: String, image: Image, color: Color = .black) {
        self.label = label
        self.image = image
        self.gradient = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: color.opacity(0.7), location: 0),
                .init(color: .clear, location: 0.4)
            ]),
            startPoint: .bottom,
            endPoint: .top
        )
    }
    
    let label: String
    let image: Image
    let gradient: LinearGradient
    
    var body: some View {
        ZStack(alignment: .bottom) {
            
//            image
//                .resizable()
//                .scaledToFit()
//                .overlay {
//                    ZStack(alignment: .bottom) {
//                        image
//                            .resizable()
//                            .scaledToFit()
//                            .blur(radius: 50)
//                            .clipped()
//                            .mask(gradient)
//                        
//                        gradient
//                    }
//                }
            
            image
                .resizable()
                .scaledToFit()
                .glur(offset: 0.7)
            
            Text(label)
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    struct BlurView: UIViewRepresentable {
        var style: UIBlurEffect.Style
        
        func makeUIView(context: Context) -> UIVisualEffectView {
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: style))
            blurView.backgroundColor = UIColor.black.withAlphaComponent(0.2) // Softening the effect
            return blurView
        }
        
        func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
    }
}

#Preview {
    HeroImage("Apple Retail", image: Image(.test), color: .blue)
}

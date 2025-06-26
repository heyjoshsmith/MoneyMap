//
//  PlaygroundView.swift
//  MoneyMap
//
//  Created by Josh Smith on 6/19/25.
//

import SwiftUI

struct PlaygroundView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(.test)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: 280)
                .clipped()
                .backgroundExtensionEffect()
            ZStack {
                Rectangle()
                    .backgroundExtensionEffect()
                    .ignoresSafeArea()
                VStack {
                    Text("Text on top of background effect")
                        .font(.title)
                        .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .top)
    }
}

#Preview {
    PlaygroundView()
}

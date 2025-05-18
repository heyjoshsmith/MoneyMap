//
//  URLCarousel.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/17/25.
//

import SwiftUI
import MoneyMapShared

struct URLCarousel: View {
    
    var goal: Goal
    
    init(for goal: Goal) {
        self.goal = goal
    }
    
    @State private var pastedLinks: [URL] = []

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Links")
                    .fontWeight(.semibold)
                Spacer()
                Button("Paste", systemImage: "document.on.clipboard", action: pasteLinks)
                    .imageScale(.small)
                    .foregroundStyle(Color.accentColor)
                    .font(.callout)
            }
            .font(.title3)
            if let urls = goal.urls {
                ScrollView(.horizontal) {
                    HStack (spacing: 10) {
                        ForEach(urls, id: \.self) { url in
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "N/A")
                                    .font(.callout)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(Color.primary)
                                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                    .clipShape(.rect(cornerRadius: 25))
                            }
                        }
                    }
                }
            } else {
                Text("Got a specific item in mind? Add the link here! You can add as many links as you like.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .foregroundColor(Color.primary)
        .cornerRadius(10)
        .gridCellColumns(2)
    }
    
    private func pasteLinks() {
        if let clipboardText = UIPasteboard.general.string {
            let detectedLinks = extractURLs(from: clipboardText)
            if let urls = goal.urls {
                goal.urls?.append(contentsOf: detectedLinks)
            } else {
                goal.urls = detectedLinks
            }
        }
    }

    private func extractURLs(from text: String) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) ?? []
        
        return matches.compactMap { match -> URL? in
            guard let range = Range(match.range, in: text) else { return nil }
            return URL(string: String(text[range]))
        }
    }
}

#Preview {
    URLCarousel(for: Goal("Standing Desk", targetAmount: 500, deadline: .now, weight: 1.0, imageURL: nil, paydaysUntil: 6))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
}

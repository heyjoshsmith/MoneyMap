//
//  URLCarousel.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/17/25.
//

import SwiftUI


struct URLCarousel: View {
    
    var goal: Goal
    
    init(for goal: Goal) {
        self.goal = goal
    }
    
    @State private var pastedLinks: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Links", systemImage: "link")
                    .font(.headline)
                Spacer()
                Button(action: pasteLinks) {
                    Label("Paste", systemImage: "document.on.clipboard")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let urls = goal.urls, !urls.isEmpty {
                ScrollView(.horizontal) {
                    HStack (spacing: 10) {
                        ForEach(urls, id: \.self) { url in
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                Text(url.host?.replacingOccurrences(of: "www.", with: "") ?? "N/A")
                                    .font(.callout)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(Color.primary)
                                    .background(MoneyMapDesign.controlBackground)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                Text("Paste product, travel, or savings links here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoneyMapDesign.surfaceBackground)
        .foregroundColor(Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius)
                .stroke(MoneyMapDesign.separator, lineWidth: 1)
        }
    }
    
    private func pasteLinks() {
        if let clipboardText = UIPasteboard.general.string {
            let detectedLinks = extractURLs(from: clipboardText)
            if goal.urls != nil {
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
    URLCarousel(for: Goal("Standing Desk", targetAmount: 500, deadline: .now, weight: 1.0, paydaysUntil: 6))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoneyMapDesign.groupedBackground)
}

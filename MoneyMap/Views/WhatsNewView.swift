//
//  WhatsNewView.swift
//  MoneyMap
//
//  Created by Codex on 3/4/26.
//

import SwiftUI

struct WhatsNewView: View {
    let releases: [WhatsNewRelease]
    let onDone: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                ForEach(releases) { release in
                    Section {
                        ForEach(release.highlights, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.blue)
                                    .padding(.top, 2)
                                Text(item)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Version \(release.version)")
                            Text(release.releaseDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("What's New")
            .toolbar {
                if let onDone {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done", action: onDone)
                    }
                }
            }
        }
    }
}

#Preview {
    WhatsNewView(releases: WhatsNewRepository.releases, onDone: nil)
}

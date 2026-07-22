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
                    if !release.featuredQuestions.isEmpty {
                        Section("Try Asking") {
                            ForEach(release.featuredQuestions, id: \.self) { item in
                                Label(item, systemImage: "waveform")
                                    .padding(.vertical, 2)
                            }
                        }
                        .listRowBackground(MoneyMapDesign.surfaceBackground)
                    }
                    Section {
                        ForEach(release.highlights, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(MoneyMapDesign.calmGreen)
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
                    .listRowBackground(MoneyMapDesign.surfaceBackground)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
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

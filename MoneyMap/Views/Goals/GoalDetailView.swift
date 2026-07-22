//
//  GoalDetailView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI
import PhotosUI
import AppIntents
//import Glur


struct GoalDetailView: View {
    
    init(_ goal: Goal) {
        self.goal = goal
    }
    
    let goal: Goal
    
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    
    @State private var choosingImage: Bool = false
    
    @State private var creatingImage: Bool = false
    @State private var imageURL: URL?
    
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var testing = false
    
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: MoneyMapDesign.sectionSpacing) {
                    
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(MoneyMapDesign.attentionRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(MoneyMapDesign.surfaceBackground, in: RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius))
                            .padding(.horizontal, MoneyMapDesign.sectionSpacing)
                    }
                    
                    Button {
                        choosingImage.toggle()
                    } label: {
                        goalHero
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, MoneyMapDesign.sectionSpacing)

                    GoalDetailProgressPanel(goal: goal)

                    GridView(goal, choosingImage: $choosingImage)
                }
                .frame(width: proxy.size.width, alignment: .leading)
                .clipped()
                .padding(.vertical, MoneyMapDesign.sectionSpacing)
            }
            .background(MoneyMapDesign.groupedBackground)
        }
        .background(MoneyMapDesign.groupedBackground)
        .navigationTitle(goal.name ?? "Goal Details")
        .toolbarTitleDisplayMode(.inline)
        .userActivity("com.heyjoshsmith.MoneyMap.viewingGoal") { activity in
            let entity = GoalEntity(goal)
            activity.title = "Viewing \(entity.name)"
            activity.appEntityIdentifier = EntityIdentifier(for: entity)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    ActivityFeedView(title: "Goal History", entityID: goal.id, entityTypes: [.goal])
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .sheet(isPresented: $choosingImage) {
            
            MyPhotoPicker(selection: $selectedItem) { imageType in
                choosingImage.toggle()
                switch imageType {
                case .imagePlayground:
                    creatingImage.toggle()
                case .photos:
                    print("Launching PhotosPicker")
                }
            }
            .presentationDetents([.fraction(0.3)])
            
        }
        .imagePlaygroundSheet(isPresented: $creatingImage, concept: goal.name ?? "", onCompletion: { url in
            Task {
                if let data = try? Data(contentsOf: url) {
                    goal.imageData = data
                    selectedImage = UIImage(data: data)
                }
                // Optionally, for legacy migration support:
                self.imageURL = url
            }
        })
        .onChange(of: selectedItem) { oldItem, newItem in
            Task {
                await loadImage(newItem)
            }
        }
    }

    @ViewBuilder
    private var goalHero: some View {
        ZStack {
            if let uiImage = goal.uiImage {
                heroImage(Image(uiImage: uiImage))
            } else if let selectedImage {
                heroImage(Image(uiImage: selectedImage))
            } else if isLoading {
                ProgressView("Loading Image...")
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(MoneyMapDesign.surfaceBackground)
            } else if testing {
                heroImage(Image(.test))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.system(size: 44, weight: .semibold))
                    Text(goal.name ?? "Savings Goal")
                        .font(.title3.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(MoneyMapDesign.moneyGradient)
            }

            VStack {
                Spacer()
                HStack {
                    Label("Change Image", systemImage: "photo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.35), in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MoneyMapDesign.sectionCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MoneyMapDesign.sectionCornerRadius)
                .stroke(MoneyMapDesign.separator, lineWidth: 1)
        }
    }

    private func heroImage(_ image: Image) -> some View {
        GeometryReader { proxy in
            image
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(MoneyMapDesign.controlBackground)
    }

    private struct GoalDetailProgressPanel: View {
        let goal: Goal

        private var progressValue: Double {
            min(max(goal.progress(), 0), 1)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Saved")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        MoneyMapMoneyText(amount: goal.amountSaved, font: .title2.weight(.semibold))
                    }

                    Spacer(minLength: 8)

                    Text(progressValue.formatted(.percent.precision(.fractionLength(0))))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(MoneyMapDesign.calmGreen)
                }

                ProgressView(value: progressValue)
                    .tint(MoneyMapDesign.calmGreen)

                HStack(spacing: MoneyMapDesign.compactSpacing) {
                    MoneyMapMetricTile(
                        title: "Target",
                        value: MoneyMapFormatters.currencyString(for: goal.targetAmount ?? 0),
                        systemImage: "target",
                        detail: goal.deadline.map { "By \(MoneyMapFormatters.mediumDateString(for: $0))" } ?? "No deadline set",
                        tint: MoneyMapDesign.calmGreen
                    )
                    MoneyMapMetricTile(
                        title: "Remaining",
                        value: MoneyMapFormatters.currencyString(for: goal.remainingAmount),
                        systemImage: "dollarsign.circle",
                        detail: goal.amountPerPaycheck.map { "\(MoneyMapFormatters.currencyString(for: $0)) per paycheck" } ?? "Set payday for pacing",
                        tint: .blue
                    )
                }
            }
            .padding(14)
            .background(MoneyMapDesign.surfaceBackground, in: RoundedRectangle(cornerRadius: MoneyMapDesign.sectionCornerRadius))
            .padding(.horizontal, MoneyMapDesign.sectionSpacing)
            .accessibilityElement(children: .combine)
        }
    }

    // Main Functions
    
    func loadImage(_ newItem: PhotosPickerItem?) async {
        isLoading = true
        choosingImage = false
        defer { isLoading = false }

        guard let newItem else {
            errorMessage = "No image selected"
            print("Error: No item selected")
            return
        }

        do {
            if let data = try await newItem.loadTransferable(type: Data.self) {
                selectedImage = UIImage(data: data)
                // Save image data directly into the Goal for CloudKit sync
                goal.imageData = data
            } else {
                errorMessage = "Unable to load image"
            }
        } catch {
            errorMessage = "Failed to load image: \(error.localizedDescription)"
            print("Error: \(error.localizedDescription)")
        }
    }
}

#Preview("Goal Details") {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    NavigationStack {
        GoalDetailView(.init("New Couch", targetAmount: 3000, deadline: .distantFuture, weight: 1.0, paydaysUntil: paydayManager.numberOfPaydaysUntil(.distantFuture)))
    }
    .environmentObject(paydayManager)
    .modelContainer(container)
}

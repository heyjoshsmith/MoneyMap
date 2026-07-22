//
//  AddGoalView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI
import SwiftData
import ImagePlayground
import PhotosUI


struct AddGoalView: View {
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @EnvironmentObject var paydayManager: PaydayManager
    @Environment(\.modelContext) var modelContext
    
    @State private var name: String = ""
    @State private var targetAmount: Double? = nil
    @State private var deadline: Date = Date().addingTimeInterval(60*60*24*30) // Default: one month from now
    @State private var priority: Double = 1.0
    
    @FocusState private var focused: Bool
    
    @State private var creatingImage: Bool = false
    
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    @State private var showingPriorityOptions = false
    @State private var showingImageOptions = false
    
    var body: some View {
        Form {
            
            if paydayManager.nextPayday == nil {
                Section("Before You Plan") {
                    Text("You can create this goal now. Add your payday later if you want paycheck pacing and better recommendations.")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }
                
            Section(header: Text("Goal Details")) {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Name", text: $name)
                        .submitLabel(.next)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Target Amount")
                    Spacer()
                    TextField("Target Amount", value: $targetAmount, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .toolbar {
                            ToolbarItem(placement: .keyboard) {
                                HStack {
                                    Spacer()
                                    Button("Done") {
                                        focused = false
                                    }
                                }
                            }
                        }
                }
                
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)
            
            Section("Target Date") {
                DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                
                if paydayManager.nextPayday != nil && computedPaydayCount == nil {
                    Text("Deadline must be after your next payday.")
                        .foregroundStyle(MoneyMapDesign.attentionRed)
                }
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)
            
            Section("More Options") {
                DisclosureGroup("Priority", isExpanded: $showingPriorityOptions) {
                    Picker("Priority", selection: $priority) {
                        HStack(spacing: 15) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(MoneyMapDesign.attentionRed)
                            Text("High")
                        }
                        .tag(2.0)

                        HStack(spacing: 15) {
                            Image(systemName: "flag")
                                .foregroundStyle(.orange)
                            Text("Medium")
                        }
                        .tag(1.0)

                        HStack(spacing: 15) {
                            Image(systemName: "circle.dashed")
                                .foregroundStyle(.gray)
                            Text("Low")
                        }
                        .tag(0.5)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                DisclosureGroup("Image", isExpanded: $showingImageOptions) {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: MoneyMapDesign.controlCornerRadius))
                            .listRowInsets(EdgeInsets())

                        Button("Remove Image") {
                            selectedItem = nil
                            selectedImage = nil
                        }
                    } else {
                        imagePicker
                    }
                }
            }
            .listRowBackground(MoneyMapDesign.surfaceBackground)
            
            if let errorMessage = errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(MoneyMapDesign.attentionRed)
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(MoneyMapDesign.groupedBackground)
        .navigationTitle("New Goal")
        .imagePlaygroundSheet(isPresented: $creatingImage, concept: name, onCompletion: { url in
            Task {
                if let data = try? Data(contentsOf: url) {
                    selectedImage = UIImage(data: data)
                }
            }
        })
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if paydayManager.nextPayday != nil && computedPaydayCount == nil {
                        errorMessage = "Deadline must be after your next payday."
                        return
                    }
                    guard let target = targetAmount, target > 0 else {
                        errorMessage = "Enter a valid target amount."
                        return
                    }
                    
                    let paydaysUntil = paydayManager.nextPayday == nil ? nil : paydayManager.numberOfPaydaysUntil(deadline)
                    let newGoal = Goal(name.isEmpty ? nil : name, targetAmount: target, deadline: deadline, weight: priority, paydaysUntil: paydaysUntil, imageData: selectedImage?.jpegData(compressionQuality: 0.8))
                    modelContext.insert(newGoal)
                    AuditService.logGoalCreated(newGoal, context: modelContext)
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .onChange(of: selectedItem) { oldItem, newItem in
            Task {
                isLoading = true
                defer { isLoading = false }
                
                errorMessage = nil

                guard let newItem else {
                    errorMessage = "No image selected"
                    print("Error: No item selected")
                    return
                }

                do {

                    if let data = try await newItem.loadTransferable(type: Data.self){
                        selectedImage = UIImage(data: data)
                    } else {
                        errorMessage = "Unable to load image"
                    }
                    
                } catch {
                    errorMessage = "Failed to load image: \(error.localizedDescription)"
                    print("Error: \(error.localizedDescription)")
                }
            }
        }
        
    }
    
    /// Computes the total number of paydays between the next payday and the selected deadline.
    var computedPaydayCount: Int? {
        guard paydayManager.nextPayday != nil else { return nil }
        let count = paydayManager.numberOfPaydaysUntil(deadline)
        return count > 0 ? count : nil
    }
    
    var imagePicker: some View {
        Group {
            if supportsImagePlayground {
                Button {
                    creatingImage = true
                } label: {
                    MoneyMapActionListRow(
                        title: "Image Playground",
                        detail: "Generate an image for this goal.",
                        systemImage: "apple.image.playground",
                        tint: .pink
                    )
                }
                .buttonStyle(.plain)
            }
            PhotosPicker(selection: $selectedItem, matching: .images) {
                MoneyMapActionListRow(
                    title: "Photos",
                    detail: "Choose an image from your photo library.",
                    systemImage: "photo.on.rectangle.angled",
                    tint: .blue
                )
            }
        }
    }
    
}

#Preview("Add Goal") {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    NavigationStack {
        AddGoalView()
    }
    .environmentObject(paydayManager)
    .modelContainer(container)
}

//
//  AddGoalView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI
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
    @State private var imageURL: URL?
    
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    @State private var choosingSavedImage: Bool = false
    
    var body: some View {
        Form {
            
            if paydayManager.nextPayday == nil {
                Section("Warning") {
                    Text("Please set your next payday in the settings first.")
                        .foregroundColor(.red)
                }
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
            
            Section("Deadline") {
                DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                
                if paydayManager.nextPayday != nil && computedPaydayCount == nil {
                    Text("Deadline must be after your next payday.")
                        .foregroundColor(.red)
                }
            }
            
            Section("Priority") {
                Picker("Priority", selection: $priority) {
                    HStack(spacing: 15) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)  // ✅ Ensures red icon
                        Text("High")
                    }
                    .tag(2.0)

                    HStack(spacing: 15) {
                        Image(systemName: "flag")
                            .foregroundStyle(.orange)  // ✅ Medium priority color
                        Text("Medium")
                    }
                    .tag(1.0)

                    HStack(spacing: 15) {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.gray)  // ✅ Low priority color
                        Text("Low")
                    }
                    .tag(0.5)
                }
                .pickerStyle(.inline) // ✅ Ensures SwiftUI respects custom styling
                .labelsHidden()
            }
            
            Section {
                if let imageURL {
                    AsyncImage(url: imageURL) { image in
                        image.resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .listRowInsets(EdgeInsets())
                } else {
                    imagePicker
                }
            } header: {
                HStack {
                    Text("Image")
                    if (imageURL != nil) {
                        Spacer()
                        Button("Remove") {
                            selectedItem = nil
                            selectedImage = nil
                            imageURL = nil
                        }
                        .textCase(.none)
                        .font(.callout)
                    }
                }
            }
            
            if let errorMessage = errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("New Goal")
        .imagePlaygroundSheet(isPresented: $creatingImage, concept: name, onCompletion: { url in
            self.imageURL = saveImageToDocuments(originalURL: url)
        })
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard paydayManager.nextPayday != nil else {
                        errorMessage = "Set your next payday first."
                        return
                    }
                    guard computedPaydayCount != nil else {
                        errorMessage = "Deadline must be after your next payday."
                        return
                    }
                    guard let target = targetAmount, target > 0 else {
                        errorMessage = "Enter a valid target amount."
                        return
                    }
                    
                    let newGoal = Goal(name.isEmpty ? nil : name, targetAmount: target, deadline: deadline, weight: priority, imageURL: imageURL, paydaysUntil: paydayManager.numberOfPaydaysUntil(deadline))
                    modelContext.insert(newGoal)
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
                        
                        // Attempt to load image as URL (optional)
                        let url = try? await newItem.loadTransferable(type: URL.self)

                        // Save using URL if available, otherwise use Data
                        let localURL = saveImageToDocuments(originalURL: url, imageData: data)
                        
                        if let localURL {
                            imageURL = localURL
                        } else {
                            errorMessage = "Unable to save image to local storage"
                        }
                        
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
            Button {
                creatingImage = true
            } label: {
                HStack {
                    Image(systemName: "apple.image.playground")
                        .frame(width: 27, alignment: .center)
                        .foregroundStyle(.pink)
                        
                    Text("Image Playground")
                        .foregroundStyle(Color.primary)
                }
            }
            PhotosPicker(selection: $selectedItem, matching: .images) {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .frame(width: 27, alignment: .center)
                        .foregroundStyle(.blue)
                        
                    Text("Photos")
                        .foregroundStyle(Color.primary)
                }
            }
            Button {
                
            } label: {
                HStack {
                    Image(systemName: "photo.badge.checkmark")
                        .frame(width: 27, alignment: .center)
                        .foregroundStyle(.green)
                        
                    Text("Saved Images")
                        .foregroundStyle(Color.primary)
                }
            }
        }
    }
    
}

func saveImageToDocuments(originalURL: URL? = nil, imageData: Data? = nil) -> URL? {
    let fileManager = FileManager.default
    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

    // Determine the destination filename
    let filename: String
    if let originalURL {
        filename = originalURL.lastPathComponent
    } else {
        filename = UUID().uuidString + ".jpg" // Generate unique filename for data-based images
    }

    let destinationURL = documentsURL.appendingPathComponent(filename)

    do {
        if let originalURL {
            // Move the file from its original location to the Documents directory
            try fileManager.moveItem(at: originalURL, to: destinationURL)
        } else if let imageData {
            // Save image data directly to the Documents directory
            try imageData.write(to: destinationURL)
        } else {
            print("Error: No valid URL or image data provided")
            return nil
        }
        return destinationURL
    } catch {
        print("Error saving image:", error)
        return nil
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

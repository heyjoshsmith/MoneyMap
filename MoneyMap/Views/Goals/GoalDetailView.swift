//
//  GoalDetailView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI
import PhotosUI
import Glur
import MoneyMapShared

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
    @State private var choosingSavedImage: Bool = false
    @State private var savedFiles = 0
    @State private var testing = false
    
    var body: some View {
        
        ScrollView {
            VStack {
                
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(.rect(cornerRadius: 10))
                        .padding()
                }
                
                ZStack {
                    
                    Text("Saved Files: \(savedFiles)")
                        .opacity(0)
                    
                    if let image = goal.loadImage() {
                        HeroImage(goal.name ?? "", image: Image(uiImage: image))
                    } else if let selectedImage {
                        HeroImage(goal.name ?? "", image: Image(uiImage: selectedImage))
                    } else if isLoading {
                        ProgressView("Loading Image...")
                    } else if testing {
                        HeroImage(goal.name ?? "Test Goal", image: Image(.test))
                    }
                    
                }
                .onTapGesture {
                    print("Loading Saved Files: \(savedFiles)")
                    choosingImage.toggle()
                }
                
                GridView(goal, choosingImage: $choosingImage)
                
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Goal Details")
        .toolbarTitleDisplayMode(.inline)
        .onAppear {
            savedFiles = getSavedFiles().count
        }
        .sheet(isPresented: $choosingImage) {
            
            MyPhotoPicker(selection: $selectedItem) { imageType in
                choosingImage.toggle()
                switch imageType {
                case .imagePlayground:
                    creatingImage.toggle()
                case .savedImages:
                    choosingSavedImage.toggle()
                case .photos:
                    print("Lauching PhotosPicker")
                }
            }
            .presentationDetents([.fraction(0.3)])
            
        }
        .imagePlaygroundSheet(isPresented: $creatingImage, concept: goal.name ?? "", onCompletion: { url in
            self.imageURL = saveImageToDocuments(originalURL: url)
        })
        .sheet(isPresented: $choosingSavedImage) {
            ChooseImageView() { url in
                goal.imageFileName = url.lastPathComponent
            }
        }
        .onChange(of: selectedItem) { oldItem, newItem in
            Task {
                await loadImage(newItem)
            }
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
            
            if let data = try await newItem.loadTransferable(type: Data.self){
                selectedImage = UIImage(data: data)
                
                // Attempt to load image as URL (optional)
                let url = try? await newItem.loadTransferable(type: URL.self)
                
                // Save using URL if available, otherwise use Data
                let localURL = saveImageToDocuments(originalURL: url, imageData: data)
                
                if let localURL {
                    goal.imageFileName = localURL.lastPathComponent
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
    
    
    
    // Custom Views
    
    private struct ChooseImageView: View {
        
        let onSelect: (URL) -> Void
        
        @State private var savedFiles: [URL] = []
        
        var body: some View {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: [GridItem(), GridItem()]) {
                        ForEach(savedFiles, id: \.self) { fileURL in
                            Button {
                                onSelect(fileURL)
                                dismiss()
                            } label: {
                                if let uiImage = loadImage(from: fileURL) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                        .cornerRadius(8)
                                } else {
                                    Image(systemName: "doc.fill")
                                        .foregroundColor(.blue)
                                        .font(.title2)
                                        .frame(maxWidth: .infinity)
                                        .background(Color(UIColor.secondarySystemGroupedBackground))
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Saved Images")
                .onAppear {
                    savedFiles = getSavedFiles()
                }
            }
        }
        
        // Tries to load an image if it's an image file
        func loadImage(from url: URL) -> UIImage? {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { return nil }
            return image
        }
        
        @Environment(\.dismiss) private var dismiss
        
    }
    
}

func getSavedFiles() -> [URL] {
    let fileManager = FileManager.default
    // Point at the shared App Group container's Images directory
    guard let groupContainer = fileManager
        .containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap")?
        .appendingPathComponent("Images", isDirectory: true) else {
            print("Error: Could not locate shared Images container")
            return []
    }
    do {
        let files = try fileManager.contentsOfDirectory(at: groupContainer, includingPropertiesForKeys: nil)
        print("Found \(files.count) files in shared Images directory: \(groupContainer.path)")
        return files
    } catch {
        print("Error listing files in shared container:", error)
        return []
    }
}

#Preview("Goal Details") {
    
    let (container, paydayManager) = PreviewDataProvider.createContainer()
    
    NavigationStack {
        GoalDetailView(.init("New Couch", targetAmount: 3000, deadline: .distantFuture, weight: 1.0, imageURL: nil, paydaysUntil: paydayManager.numberOfPaydaysUntil(.distantFuture)))
    }
    .environmentObject(paydayManager)
    .modelContainer(container)
}

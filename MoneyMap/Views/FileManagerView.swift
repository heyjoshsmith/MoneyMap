//
//  FileManagerView.swift
//  MoneyMap
//
//  Created by Josh Smith on 2/12/25.
//

import SwiftUI

struct FileManagerView: View {
    
    @State private var savedFiles: [URL] = []
    @State private var showingDeleteAlert = false
    @State private var imageURLtoDelete: URL?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if savedFiles.isEmpty {
                        MoneyMapEmptyState(
                            title: "No Saved Files",
                            message: "Saved images and files will appear here.",
                            systemImage: "folder"
                        )
                    } else {
                        ForEach(savedFiles, id: \.self) { fileURL in
                            HStack(spacing: 12) {
                                if let uiImage = loadImage(from: fileURL) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: MoneyMapDesign.cornerRadius))
                                } else {
                                    Image(systemName: "doc.fill")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 52, height: 52)
                                        .background(MoneyMapDesign.controlBackground, in: RoundedRectangle(cornerRadius: MoneyMapDesign.cornerRadius))
                                }

                                Text(fileURL.lastPathComponent)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.vertical, 2)
                            .swipeActions {
                                Button(role: .destructive) {
                                    self.imageURLtoDelete = fileURL
                                    self.showingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listRowBackground(MoneyMapDesign.surfaceBackground)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MoneyMapDesign.groupedBackground)
            .navigationTitle("Saved Files")
            .onAppear {
                savedFiles = getSavedFiles()
            }
        }
        .alert("Delete Image", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    if let imageURLtoDelete {
                        deleteFile(at: imageURLtoDelete)
                        savedFiles = getSavedFiles() // Refresh list after deletion
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this image? This action cannot be undone.")
        }

    }
    
    func getSavedFiles() -> [URL] {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        do {
            let files = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            return files // Returns all files, regardless of type
        } catch {
            print("Error listing files:", error)
            return []
        }
    }
    
    // Tries to load an image if it's an image file
    func loadImage(from url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        return image
    }
    
    // Deletes any file type
    func deleteFile(at url: URL) {
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: url)
            print("Deleted:", url.lastPathComponent)
        } catch {
            print("Error deleting file:", error)
        }
    }
}

#Preview {
    FileManagerView()
}

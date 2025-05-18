//
//  MoneyMapShared.swift
//  MoneyMapShared
//
//  Created by Josh Smith on 4/30/25.
//

import Foundation

func saveImageToDocuments(originalURL: URL? = nil, imageData: Data? = nil) -> URL? {
    let fileManager = FileManager.default
    // Use shared App Group container
    guard let groupContainer = fileManager
        .containerURL(forSecurityApplicationGroupIdentifier: "group.com.heyjoshsmith.MoneyMap") else {
        print("Error: Could not locate group container")
        return nil
    }
    // Create an "Images" subdirectory if needed
    let imagesDir = groupContainer.appendingPathComponent("Images", isDirectory: true)
    do {
        try fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    } catch {
        print("Error creating Images directory:", error)
    }
    // Determine filename
    let filename: String
    if let original = originalURL {
        filename = original.lastPathComponent
    } else {
        filename = UUID().uuidString + ".jpg"
    }
    let destinationURL = imagesDir.appendingPathComponent(filename)
    do {
        if let original = originalURL {
            try fileManager.moveItem(at: original, to: destinationURL)
        } else if let data = imageData {
            try data.write(to: destinationURL)
        } else {
            print("Error: No valid URL or image data provided")
            return nil
        }
        return destinationURL
    } catch {
        print("Error saving image to shared container:", error)
        return nil
    }
}

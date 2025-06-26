//
//  BillView.swift
//  MoneyMap
//
//  Created by Josh Smith on 3/26/25.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ImagePlayground

struct BillView: View {
    
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    
    var bill: Bill
    
    @State private var animate = false
    @State private var editingLimit = false
    @State private var selectedImage: UIImage? = nil
    @State private var imagePickerSource: ImagePickerSource? = nil
    @State private var cardLimit = ""
    @State private var creatingImage: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                billHeaderSection
                
                VStack(spacing: 10) {
                    
                    // Credit Card Details (if applicable)
                    creditCardDetailsSection
                    
                    // Recurrence
                    recurrenceSection
                    
                }
                .padding()
            }
        }
        .navigationTitle("Bill Details")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Add Image") {
                        ForEach(ImagePickerSource.allCases, id: \.self) { source in
                            Button {
                                if source == .playground {
                                    creatingImage = true
                                } else {
                                    imagePickerSource = source
                                }
                            } label: {
                                Label(source.title, systemImage: source.systemImage)
                                    .foregroundStyle(source.color)
                            }
                        }
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis")
                }
            }
        }
        .alert("Card Limit", isPresented: $editingLimit) {
            TextField("New Limit", text: $cardLimit)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let newLimit = Double(cardLimit) {
                    // TODO: Update card limit via binding or callback. Cannot mutate bill here.
                }
            }
        } message: {
            if let details = bill.creditCardDetails {
                Text("What is your new card limit? Your current limit is \(details.creditLimit, format: .currency(code: "USD"))")
            }
        }
        .sheet(item: $imagePickerSource) { source in
            switch source {
            case .camera:
                ImagePicker(sourceType: .camera) { image in
                    selectedImage = image
                    imagePickerSource = nil
                    bill.setImage(image)
                }
            case .photoLibrary:
                ImagePicker(sourceType: .photoLibrary) { image in
                    selectedImage = image
                    imagePickerSource = nil
                    bill.setImage(image)
                }
            case .files:
                DocumentPicker { image in
                    selectedImage = image
                    imagePickerSource = nil
                    bill.setImage(image)
                }
            case .playground:
                // Present the official Image Playground UI via a dedicated view
                EmptyView()
            }
        }
        .imagePlaygroundSheet(isPresented: $creatingImage, onCompletion: { url in
            Task {
                if let data = try? Data(contentsOf: url),
                    let image = UIImage(data: data) {
                    selectedImage = image
                    bill.setImage(image)
                }
            }
        })
    }
    
    private var billHeaderSection: some View {
        ZStack {
            if let billImage = bill.image {
                billImage
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 300)
                    .clipped()
                    .overlay(
                        Rectangle()
                            .fill(Color.black.opacity(0.4))
                    )
            } else {
                Rectangle()
                    .fill(bill.category?.color.gradient ?? Color.gray.gradient)
            }

            VStack(spacing: 10) {
                if bill.category != .creditCard {
                    Text(bill.amount ?? 0, format: .currency(code: "USD"))
                        .font(.title.weight(.medium))
                }
                Label(bill.name ?? "Untitled", systemImage: bill.category?.icon ?? "questionmark.circle")
                    .font(.largeTitle.weight(.semibold))
                Text(bill.dueDate ?? Date(), style: .date)
                    .opacity(0.7)
            }
            .scaleEffect(animate ? 1.0 : 0.75)
            .opacity(animate ? 1.0 : 0.0)
            .foregroundStyle(.white)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animate = true
            }
        }
        .frame(maxWidth: .infinity, idealHeight: 300)
    }
    
    private var creditCardDetailsSection: some View {
        Group {
            if bill.category == .creditCard, let details = bill.creditCardDetails {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Card Balance")
                            .font(.title3.weight(.medium))
                        Text("\(details.cardBalance.abbreviatedCurrency) of \(details.creditLimit.abbreviatedCurrency)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Gauge(value: details.cardBalance, in: 0...details.creditLimit) {
                        Text(details.utilization, format: .percent.precision(.fractionLength(0)))
                            .font(.callout.weight(.medium))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(aboveMax ? .red : .green)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 15))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
                .padding(.bottom)
                
                HStack {
                    Text("Max Usage")
                    Spacer()
                    Text(details.creditLimit * 0.3, format: .currency(code: "USD"))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                
                if let recommendedPayment {
                    HStack {
                        Text("Recommended Payment")
                        Spacer()
                        Text(recommendedPayment, format: .currency(code: "USD"))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    private var recurrenceSection: some View {
        HStack {
            Text("Recurrence")
            Spacer()
            Text("Every \(bill.recurrenceInterval ?? 1) \(bill.recurrenceUnit?.rawValue ?? "")\((bill.recurrenceInterval ?? 1) > 1 ? "s" : "")")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }
    
    var recommendedPayment: Double? {
        
        guard let details = bill.creditCardDetails else {
            return nil
        }
        
        let payment = details.cardBalance - (details.creditLimit * 0.3)
        
        if payment < 0 {
            return nil
        } else {
            return payment
        }
    }
    
    var aboveMax: Bool {
        if let creditCardDetails = bill.creditCardDetails {
            
            return (creditCardDetails.cardBalance / creditCardDetails.creditLimit) >= 0.3
            
        }
        
        return false
    }
    
    var utilizationIcon: some View {
        HStack {
            if let creditCardDetails = bill.creditCardDetails {
                
                let above = (creditCardDetails.cardBalance / creditCardDetails.creditLimit) >= 0.3
                
                if above {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                
                Text((creditCardDetails.cardBalance / creditCardDetails.creditLimit), format: .percent.precision(.fractionLength(0)))
                
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .foregroundStyle(.gray)
                Text("N/A")
            }
        }
    }
}

enum ImagePickerSource: Int, Identifiable, CaseIterable {
    case camera, photoLibrary, files, playground
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .camera: return "Camera"
        case .photoLibrary: return "Photos"
        case .files: return "Files"
        case .playground: return "Playground"
        }
    }
    
    var systemImage: String {
        switch self {
        case .camera: return "camera"
        case .photoLibrary: return "photo.on.rectangle"
        case .files: return "doc"
        case .playground: return "paintpalette"
        }
    }
    
    var color: Color {
        switch self {
        case .camera: return .blue
        case .photoLibrary: return .orange
        case .files: return .purple
        case .playground: return .green
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }

    var sourceType: UIImagePickerController.SourceType
    var onImagePicked: (UIImage) -> Void

    @Environment(\.presentationMode) private var presentationMode

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.presentationMode.wrappedValue.dismiss()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.presentationMode.wrappedValue.dismiss()
                return
            }
            
            if let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                parent.onImagePicked(image)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }

    var onImagePicked: (UIImage) -> Void

    @Environment(\.presentationMode) private var presentationMode

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = [UTType.image]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}


#Preview {
    // Create a sample bill for preview purposes
    let sampleBill = Bill(name: "Sample Bill",
                          amount: 123.45,
                          dueDate: Date(),
                          category: .creditCard,
                          recurrenceInterval: 1,
                          recurrenceUnit: .month,
                          creditCardDetails: CreditCardDetails(creditLimit: 5000, cardBalance: 1200)
    )
    NavigationStack {
        BillView(bill: sampleBill)
    }
}


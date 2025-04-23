//
//  DocumentPicker.swift
//  N7-Exam
//
//  Created by 斯利普固 on 2025/4/21.
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    var onSelect: (URL) -> Void
    var contentTypes: [UTType]
    
    init(contentTypes: [UTType], onSelect: @escaping (URL) -> Void) {
        self.contentTypes = contentTypes
        self.onSelect = onSelect
    }
    
     init(fileExtensions: [String], onSelect: @escaping (URL) -> Void) {
         self.contentTypes = fileExtensions.compactMap { UTType(filenameExtension: $0) }
         self.onSelect = onSelect
     }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onSelect: (URL) -> Void
        
        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onSelect(url)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

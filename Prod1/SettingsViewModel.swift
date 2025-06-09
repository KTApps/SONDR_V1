//
//  SettingsViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 08/06/2025.
//

import SwiftUI
import Foundation
import FirebaseStorage
import PhotosUI

protocol SettingsViewModel {
    func saveImage() async throws
    func retrieveImage()
    func signOut()
    func deleteAccount() async throws
}

extension AuthState: SettingsViewModel {
    func saveImage() async throws {
        guard let item = selectedItem else {
            return
        }
        
        guard let currentUserId = userSession?.uid else {
            return
        }
        
        guard let imageData = try await item.loadTransferable(type: Data.self) else {
            return
        }
        
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        
        let path = "\(UUID().uuidString).jpeg"
        let metaData = try await self.storageRef.child(path).putDataAsync(imageData, metadata: meta)
        
        let userDocRef = self.databaseRef.collection("users").document(currentUserId)
        
        let docSnapshot = try await userDocRef.getDocument()
        if let profilePic = docSnapshot.data()?["profilePic"] as? String {
            let oldImageRef = self.storageRef.child(profilePic)
            try? await oldImageRef.delete()
        }
        
        try await userDocRef.updateData(["profilePic": path])
    }
    
    func retrieveImage() {
        guard let currentUserId = userSession?.uid else {
            return
        }
        let userDocRef = self.databaseRef.collection("users").document(currentUserId)
        userDocRef.getDocument { document, error in
            if let error = error {
                print("func retrieveImage(): error fetching document: \(error)")
                return
            }
            guard let document = document, document.exists, let data = document.data() else {
                return
            }
            if let path = data["profilePic"] as? String {
                let imageRef = self.storageRef.child(path)
                imageRef.getData(maxSize: 10 * 1024 * 1024) { data, error in
                    if let error = error {
                        print("func retrieveImage(): error fetching imageRef: \(error)")
                        return
                    }
                    guard let data = data, let uiImage = UIImage(data: data) else {
                        print("func retrieveImage(): error converting imageRef to UiImage: \(error)")
                        return
                    }
                    DispatchQueue.main.async {
                        self.profileImage = Image(uiImage: uiImage)
                    }
                }
            }
        }
    }
    
    func signOut() {
        do {
            try self.authRef.signOut() // firebase sign out
            self.userSession = nil // takes us back to login screen
            clearData()
            
        } catch {
            print("SIGNED OUT Failed... \(error.localizedDescription)")
        }
    }

    func deleteAccount() async throws {
        if let user = self.authRef.currentUser {
            let userId = user.uid
            let userRef = self.databaseRef.collection("users").document(userId)
            try await userRef.delete()
            
            // Delete subcollections (habitData)
            let habitDataQuery = userRef.collection("CircleData")
            let habitDataDocs = try await habitDataQuery.getDocuments()
            for doc in habitDataDocs.documents {
                try await doc.reference.delete()
            }
            
            try await user.delete()
            self.userSession = nil
            clearData()
        }
    }
}

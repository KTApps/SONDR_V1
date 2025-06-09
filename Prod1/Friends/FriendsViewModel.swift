//
//  FriendsViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 08/06/2025.
//

import SwiftUI
import FirebaseFirestore

protocol FriendsViewModel {
    func addFriends(withUsername username: String) async
    func searchUsers(query: String) async
    func fetchAllFriendsData() async
    func fetchFriendData(friendUsername: String) async
    func friendColorReturn(value: String, username: String) -> Color
    func friendsCounter() async
    func friendOrFriends(friendCount: Int) async
    func retrieveFriendImage(for username: String) async -> Image?
}

extension AuthState: FriendsViewModel {
    func addFriends(withUsername username: String) async {
        // Checks if User is logged in
        guard let currentUserId = self.authRef.currentUser?.uid else {
            print("User not logged in.")
            return
        }
        
        // Broad query to fetch all user documents
        let query = self.databaseRef.collection("users")
        
        let userRef = query.document(currentUserId)
        
        do {
            let querySnapshot = try await query.getDocuments()
            
            // Check if any document has the provided email
            var usernameExists = false
            for document in querySnapshot.documents {
                if let authData = document.data()["AuthenticationData"] as? [String: Any],
                   let docUsername = authData["username"] as? String,
                   docUsername == username {
                    usernameExists = true
                    break
                }
            }
            
            // If username is not found, show error and return
            if !usernameExists {
                DispatchQueue.main.async {
                    self.addFriendsError = true
                }
                return
            }

            // Fetch the current user's friends list
            let userDoc = try await userRef.getDocument()
            var currentFriends = userDoc.data()?["Friends"] as? [String] ?? []

            // Check if friend already exists
            if currentFriends.contains(username) {
                DispatchQueue.main.async {
                    self.friendAlreadyExistsError = true
                }
                print("func addFriends(): User already exists in friends list.")
                self.friendMessage = "Friend Already Exists!"
                self.friendAdded = true
                return
            }

            // Add new friend to the 'Friends' array
            currentFriends.append(username)
            try await userRef.updateData(["Friends": FieldValue.arrayUnion([username])])

            print("func addFriends(): Successfully added friend.")
            self.friendMessage = "Friend Added!"
            self.friendAdded = true
            await fetchAllFriendsData()

        } catch {
            print("func addFriends(): Error adding friend: \(error)")
        }
    }
    
    func searchUsers(query: String) async {
        guard !query.isEmpty else {
            self.searchResults = [:] // Clear results if the query is empty
            return
        }

        let queryRef = self.databaseRef.collection("users")
            .whereField("AuthenticationData.username", isGreaterThanOrEqualTo: query)
            .whereField("AuthenticationData.username", isLessThanOrEqualTo: query + "\u{f8ff}") // Supports partial matching
        
        do {
            // Fetch the matching documents
            let querySnapshot = try await queryRef.getDocuments()

            // Clear previous search results (if you want to reset search results each time)
            self.searchResults.removeAll()

            // Iterate over the documents and extract 'username' from the 'AuthenticationData' map
            for document in querySnapshot.documents {
                if let authData = document.data()["AuthenticationData"] as? [String: Any],
                   let username = authData["username"] as? String,
                   let progressData = document.data()["Progress"] as? [String: Any],
                   let progressTimerDictionary = progressData["progressTimerDictionary"] as? [String: Int] {
                    // Sum up all the values in the progressTimerDictionary
                    let totalProgress = progressTimerDictionary.values.reduce(0, +)
                   
                    // Generate a unique key by appending 'uniqueId' and a counter
                    var uniqueKey = "\(username)_uniqueId\(0)"
                    var counter = 1
                    while self.searchResults.keys.contains(uniqueKey) {
                        uniqueKey = "\(username)_uniqueId\(counter)"
                        counter += 1
                    }
                    
                    // Update the searchResults dictionary
                    self.searchResults[uniqueKey] = totalProgress
                }
            }

        } catch {
            print("Error fetching users: \(error.localizedDescription)")
        }
    }
    
    func fetchAllFriendsData() async {
        // Checks if User is logged in
        guard let currentUserId = self.authRef.currentUser?.uid else {
            print("func fetchAllFriendsData(): User not logged in.")
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        
        do {
            let userDocSnapshot = try await userRef.getDocument()
            guard let friendsArray = userDocSnapshot.data()?["Friends"] as? [String] else {
                return
            }
            
            // Fetch habit data for all friends
            for friendUsername in friendsArray {
                await fetchFriendData(friendUsername: friendUsername)
            }
            
        } catch {
            print("func fetchAllFriendsData(): Error fetching user document: \(error.localizedDescription)")
        }
    }
    
    func fetchFriendData(friendUsername: String) async {
        let query = self.databaseRef.collection("users").whereField("AuthenticationData.username", isEqualTo: friendUsername)
        
        do {
            let querySnapshot = try await query.getDocuments()
            guard let friendDoc = querySnapshot.documents.first else {
                print("func fetchFriendData(): Friend with username \(friendUsername) not found.")
                return
            }
            
            let friendId = friendDoc.documentID
            
            // Fetch CircleData
            let circleDataRef = self.databaseRef.collection("users").document(friendId).collection("CircleData").document("\(currentYear)-\(currentDayOfYear)")
            let circleDocumentSnapshot = try await circleDataRef.getDocument()
            let circleData = circleDocumentSnapshot.data()
            
            // Fetch HabitData
            if let habitDataMap = circleData?["HabitData"] as? [String: Any] {
                let decodedHabitData = try Firestore.Decoder().decode(HabitDataModel.self, from: habitDataMap)
                DispatchQueue.main.async {
                    self.friendsHabitData[friendUsername] = decodedHabitData
                }
            }
            
            // Fetch TaskData
            if let taskDataMap = circleData?["TaskData"] as? [String: Any] {
                let decodedTaskData = try Firestore.Decoder().decode(TaskDataModel.self, from: taskDataMap)
                DispatchQueue.main.async {
                    self.friendsTaskData[friendUsername] = decodedTaskData
                }
            }
            
        } catch {
            print("func fetchFriendData(): Error fetching friend's data: \(error.localizedDescription)")
        }
    }
    
    func friendColorReturn(value: String, username: String) -> Color {
        if friendsHabitData[username]?.isHabitStriked[value] == true {
            return .blue
        } else {
            return .gray
        }
    }
    
    func friendsCounter() async {
        // Checks if User is logged in
        guard let currentUserId = self.authRef.currentUser?.uid else {
            print("User not logged in.")
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        
        do {
            let documentSnapshot = try await userRef.getDocument()
            guard let friendsArray = documentSnapshot.data()?["Friends"] as? [String] else {
                return
            }
            
            // Return the count of elements in the 'Friends' array
            self.friendCount = friendsArray.count
            await friendOrFriends(friendCount: friendsArray.count)
        } catch {
            print("Error fetching user document: \(error.localizedDescription)")
        }
    }
    
    func friendOrFriends(friendCount: Int) async {
        if friendCount == 1 {
            friendOrFriends = "Friend"
        } else {
            friendOrFriends = "Friends"
        }
    }
    
    func retrieveFriendImage(for username: String) async -> Image? {
        
        // Check if the image is already cached
        if let cachedImage = profileImageCache[username] {
            return cachedImage
        }

        // Fetch the user's document by username
        let query = databaseRef.collection("users").whereField("AuthenticationData.username", isEqualTo: username)
        
        do {
            // Fetch user document
            let snapshot = try await query.getDocuments()
            if snapshot.documents.isEmpty {
                print("No documents found for username: \(username)")
                return nil
            }
            
            guard let document = snapshot.documents.first,
                  let profilePicPath = document.data()["profilePic"] as? String else {
                return nil // If no document or profilePicPath is found
            }
                        
            // Download the image from Firebase Storage
            let imageRef = storageRef.child(profilePicPath)
            
            // Fetch image data with completion handler wrapped in async/await
            let imageData: Data? = try await withCheckedContinuation { continuation in
                imageRef.getData(maxSize: 10 * 1024 * 1024) { data, error in
                    if let error = error {
                        print("Error fetching image: \(error)")
                        continuation.resume(returning: nil) // Return nil on error
                    } else {
                        continuation.resume(returning: data) // Return the image data
                    }
                }
            }
            
            // Check if imageData was successfully fetched and convert it to UIImage
            if let data = imageData, let uiImage = UIImage(data: data) {
                let image = Image(uiImage: uiImage)
                DispatchQueue.main.async {
                    self.profileImageCache[username] = image // Cache the image
                }
                return image
            } else {
                print("Failed to convert imageData to UIImage for username: \(username)")
                return nil // If unable to convert data to UIImage
            }
            
        } catch {
            print("Error fetching profile picture for \(username): \(error)")
            return nil // If there's any error, return nil
        }
    }
}

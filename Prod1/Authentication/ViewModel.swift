//
//  AuthenticationViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 12/03/2024.
//

import SwiftUI
import Foundation
import Firebase
import FirebaseFirestoreSwift
import PhotosUI
import FirebaseStorage

//  MARK: User Input Validator
protocol AuthFormValidation {
    var isFormValid: Bool { get }
}

@MainActor
class ViewModel: ObservableObject {
    let authRef = Auth.auth()
    let databaseRef = Firestore.firestore()
    let storageRef = Storage.storage().reference()
    
    @Published var userSession: FirebaseAuth.User? = nil
    @Published var currentUser: UserObject?
    @Published var taskData: TaskData?
    @Published var progressData: ProgressData?
    @Published var habitData: HabitData?
    @Published var analytics: Analytics?
    @Published var currentYear: Int = Calendar.current.component(.year, from: Date())
    @Published var currentMonth: Int = Calendar.current.component(.month, from: Date())
    var month: String {
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "LLLL" // This gives the full month name (e.g., "September")
        return dateFormatter.string(from: date)
    }
    @Published var currentDayOfYear: Int = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
    @Published var currentDayOfWeek: Int = 0
    @Published var weekDayIndexCounter: Int = 0
    
    init() { // Runs at start of program
        Task {
            await listenForUser()
        }
        
        // Initialising weekDayIndexCounter to the current day of the week
        weekDayIndexCounter = weekdayIndex(forDayOfYear: currentDayOfYear, inYear: currentYear) ?? 0
        
        // Initialising currentDayOfWeek
        currentDayOfWeek = currentDayOfYear
    }
    
    
    //  MARK: Clear Data
    func clearData() {
        currentUser = nil
        taskData = nil
        habitData = nil
        progressTasks = []
        taskDecimalDict = [:]
        taskPercentageDict = [:]
        progressTimerDictionary = [:]
        taskMaxTime = [:]
        habitIdArray = []
        habitIdName = [:]
        isHabitStriked = [:]
        friendsHabitData = [:]
        docTitles = []
        habitStreak = 0
        cumulativeTasks = [:]
        cumulativeProg = 0
    }
    
    
    //  MARK: Listen For Data
    func listenForUser() async {
        // Checks if User is logged in
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        // Add a listener for changes to the user document
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        
        userRef.getDocument { document, error in
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
        
        userRef.addSnapshotListener { documentSnapshot, error in
            guard let document = documentSnapshot else {
                print("Error fetching document: \(error!)")
                return
            }
            guard document.exists else {
                return
            }
            
            // Fetch user data from the document
            if let userData = document.data() {
                // Fetch and decode authentication data
                if let authenticationData = userData["AuthenticationData"] as? [String: Any] {
                    do {
                        let decodedAuthenticationData = try Firestore.Decoder().decode(Prod1.UserObject.self, from: authenticationData)
                        self.currentUser = decodedAuthenticationData
                    } catch {
                        print("Error decoding AuthenticationData: \(error.localizedDescription)")
                    }
                }
                
                // Fetch and decode Analytics
                if let analytics = userData["Analytics"] as? [String: Any] {
                    do {
                        let decodedAnalytics = try Firestore.Decoder().decode(Prod1.Analytics.self, from: analytics)
                        self.dayTracker = decodedAnalytics.dayTracker
                    } catch {
                        print("Error decoding Analytics: \(error.localizedDescription)")
                    }
                }
                
                // Fetch and decode progress data
                if let progressData = userData["Progress"] as? [String: Any] {
                    do {
                        let decodedProgressData = try Firestore.Decoder().decode(Prod1.ProgressData.self, from: progressData)
                        self.progressData = decodedProgressData
                        self.progressTasks = decodedProgressData.progressTasks
                        self.progressTimerDictionary = decodedProgressData.progressTimerDictionary
                        self.taskDecimalDict = decodedProgressData.taskDecimalDict
                        self.taskMaxTime = decodedProgressData.taskMaxTime
                    } catch {
                        print("Error decoding progress data: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Add a listener for changes to the habitData subcollection
        let circleData = userRef.collection("CircleData").document("\(currentDayOfYear)")
        circleData.addSnapshotListener { documentSnapshot, error in
            guard let circleDocument = documentSnapshot else {
                print("Error fetching HabitData: \(error!)")
                return
            }
            guard circleDocument.exists else {
                return
            }
            
            if let circleData = circleDocument.data() {
                // Fetch and decode habit data
                if let habitData = circleData["HabitData"] as? [String: Any] {
                    do {
                        // Decode habit data into custom data model
                        let decodedHabitData = try Firestore.Decoder().decode(Prod1.HabitData.self, from: habitData)
                        self.habitData = decodedHabitData
                    } catch {
                        print("Error decoding HabitData: \(error.localizedDescription)")
                    }
                }
                
                // Fetch and decode task data
                if let taskData = circleData["TaskData"] as? [String: Any] {
                    do {
                        let decodedTaskData = try Firestore.Decoder().decode(Prod1.TaskData.self, from: taskData)
                        self.taskData = decodedTaskData
                        self.tasks = decodedTaskData.tasks
                        self.taskTimerDictionary = decodedTaskData.taskTimerDictionary
                    } catch {
                        print("Error decoding TaskData: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    
    //  MARK: LOG IN
    @Published var logInError: Bool = false
    func logIn(withEmail email: String, password: String) async throws {
        do {
            taskName = "Task"
            taskTime = 0
            taskString = ""
            
            let result = try await self.authRef.signIn(withEmail: email, password: password) // signs into the authenticated user from firebase
            self.userSession = result.user // user session = authenticated user
            
            Task {
                await listenForUser()
                await listenForCircleData(dayOfYear: currentDayOfWeek)
                
                await self.dayTrackerMath()
                if dayConstant < currentDayOfYear {
                    await newCircleDoc()
                }
                
                await self.fetchCircleDocRef()
            }
            self.isFriendsVisible = false
        } catch {
            self.logInError.toggle()
            print("LOG IN Failed... \(error.localizedDescription)")
        }
    }
    
    @Published var dayTracker: [Int] = []
    @Published var dayTrackerOffset: Int = 0
    @Published var habitStreak: Int = 0
    private func dayTrackerMath() async {
        // Checks if User is logged in
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        // Reference to the specific user document
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        
        // Fetch the current 'dayTracker' array from Firestore
        do {
            let document = try await userRef.getDocument()
            if document.exists {
                // Extract the current 'dayTracker' array from the 'Analytics' map
                self.dayTracker = document.get("Analytics.dayTracker") as? [Int] ?? []
                
                // Check if currentDayOfYear is equal to the last element in dayTracker
                guard self.currentDayOfYear != self.dayTracker.last else {
                    return
                }
                
                // Append currentDayOfYear to dayTracker
                self.dayTracker.append(self.currentDayOfYear)
                
                // Keep only the last two elements in dayTracker if it has more than two elements
                if self.dayTracker.count > 2 {
                    self.dayTracker = Array(self.dayTracker.suffix(2)) // dayTracker = [last 2 elements]
                }
                
                // Calculate the dayTrackerOffset
                if self.dayTracker.count >= 2 {
                    self.dayTrackerOffset = (self.dayTracker[1] - self.dayTracker[0])
                } else {
                    self.dayTrackerOffset = 0 // Set to 0 when there are fewer than 2 elements
                }
                print("dayTrackerOffset = \(self.dayTrackerOffset)")
                
                self.habitStreak = document.get("Analytics.habitStreak") as? Int ?? 0
                
                Task {
                    await self.analyticsUpdate()
                    await self.habitStreakTracker()
                }
            }
        } catch {
            print("Document does not exist")
        }
    }
    
    func habitStreakTracker() async {
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        let circleDataRef = userRef.collection("CircleData").document("\(self.currentDayOfYear - 1)")
        
        do {
            do {
                guard self.dayTrackerOffset != 0 else {
                    return
                }
                
                guard self.dayTrackerOffset == 1 else {
                    self.habitStreak = 0
                    return
                }
                
                let document = try await circleDataRef.getDocument()
                if document.exists {
                    let docData = document.data()
                    let habitData = docData?["HabitData"] as? [String: Any]
                    let isStriked = habitData?["isHabitStriked"] as? [String: Bool]
                    
                    if let isStriked = isStriked {
                        let allStriked = isStriked.values.allSatisfy { $0 == true }
                        self.habitStreak = allStriked ? self.habitStreak + 1 : 0
                    } else {
                        self.habitStreak = 0
                    }
                }
            } catch {
                self.habitStreak = 0
            }
            
            try await userRef.updateData([
                "Analytics.habitStreak" : self.habitStreak
            ])
            
        } catch {
            return
        }
    }
    
    
    //  MARK: SIGN UP
    @Published var signUpError: Bool = false
    @Published var usernameExists: Bool = false
    enum usernameExistsError: Error {
        case usernameAlreadyExists
    }
    func signUp(withEmail email: String, password: String, username: String) async throws {
        do {
            // Check if the username already exists
            let querySnapshot = try await self.databaseRef.collection("users")
                .whereField("AuthenticationData.username", isEqualTo: username)
                .getDocuments()

            if !querySnapshot.isEmpty {
                throw usernameExistsError.usernameAlreadyExists // Custom error
            }
            
            let result = try await self.authRef.createUser(withEmail: email, password: password) // Authenticates user
            self.userSession = result.user // user session = authenticated user
            
            taskName = "Task"
            taskTime = 0
            taskString = ""
            
            dayTracker = []
            
            progressTasks = []
            progressTimerDictionary = [:]
            taskDecimalDict = [:]
            taskMaxTime = [:]
            
            habitIdArray = []
            habitIdName = [:]
            isHabitStriked = [:]
            
            taskTimerDictionary = [:]
            tasks = []
            
            habitStreak = 0
            cumulativeTasks = [:]
            
            self.profileImage = nil
            
            // Store user data
            let user = UserObject(id: result.user.uid,
                                  username: username,
                                  email: email) // initializes the raw data for encoding
            let encodedUser = try Firestore.Encoder().encode(user) // encodes raw data to encrypted data
            let userRef = self.databaseRef.collection("users").document(user.id)
            try await userRef.setData(["AuthenticationData": encodedUser])
            
            let analytics = Prod1.Analytics(dayTracker: dayTracker,
                                            dayTrackerOffset: dayTrackerOffset,
                                            habitStreak: habitStreak,
                                            cumulativeTasks: cumulativeTasks)
            let encodedAnalytics = try Firestore.Encoder().encode(analytics)
            try await userRef.updateData(["Analytics": encodedAnalytics])
            
            let progress = Prod1.ProgressData(progressTasks: progressTasks,
                                              progressTimerDictionary: progressTimerDictionary,
                                              taskDecimalDict: taskDecimalDict,
                                              taskMaxTime: taskMaxTime)
            let encodedProgress = try Firestore.Encoder().encode(progress)
            try await userRef.updateData(["Progress": encodedProgress])
            
            // Create Circle Sub-Collection
            await circleSubCollection()
            Task {
                clearData()
                
                await listenForUser()
                await listenForCircleData(dayOfYear: currentDayOfWeek)
                
                await fetchCircleDocRef()
                
                dayConstant = currentDayOfYear
                dayTracker.append(currentDayOfYear)
                await analyticsUpdate()
            }
        } catch usernameExistsError.usernameAlreadyExists {
            usernameExists.toggle()
            print("SIGN UP Failed... Username already exists.")
        } catch {
            signUpError.toggle()
            print("SIGN UP Failed... \(error.localizedDescription)")
        }
    }
    
    private func analyticsUpdate() async {
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        // Reference to the specific user document
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        
        let analyticsUpdate: [String: Any] = [
            "dayTracker": self.dayTracker,
            "dayTrackerOffset": self.dayTrackerOffset,
            "habitStreak": self.habitStreak,
            "cumulativeTasks": self.cumulativeTasks
        ]
        
        do {
            try await userRef.updateData([
                "Analytics": analyticsUpdate
            ])
        } catch {
            print("Error updating document: \(error.localizedDescription)")
        }
    }
    
    //  MARK: Create Habit Sub-Collection
    private func circleSubCollection() async {
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        
        // Iterate over the next six days
        for i in 0..<7 {
            // Calculate the day of year for the current day plus 'i'
            let nextDayOfYear = currentDayOfYear + i
            
            // Construct the document reference for the current day
            let currentDayDocumentRef = userRef.collection("CircleData").document("\(nextDayOfYear)")
            
            do {
                // Check if the document for the current day already exists
                let documentSnapshot = try await currentDayDocumentRef.getDocument()
                
                // If the document for the current day doesn't exist, create it
                if !documentSnapshot.exists {
                    // Store habit data as a subcollection within the current day document
                    let habitData = Prod1.HabitData(habitIdArray: habitIdArray,
                                                    habitIdName: habitIdName,
                                                    isHabitStriked: isHabitStriked)
                    
                    let encodedHabitData = try Firestore.Encoder().encode(habitData)
                    try await currentDayDocumentRef.setData(["HabitData": encodedHabitData])
                    
                    // Store task data
                    let taskData = Prod1.TaskData(tasks: tasks,
                                                  taskTimerDictionary: taskTimerDictionary)
                    let encodedTaskData = try Firestore.Encoder().encode(taskData)
                    try await currentDayDocumentRef.updateData(["TaskData": encodedTaskData])
                    
                }
            } catch {
                print("Error checking or updating HabitData for day \(nextDayOfYear): \(error)")
            }
        }
    }
    
    @Published var dayConstant: Int = 0
    //  MARK: Create Habit Document
    private func newCircleDoc() async {
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        
        // Reference the current day document
        let currentDayDocumentRef = userRef.collection("CircleData").document("\(currentDayOfYear)")
        
        do {
            // Fetch the current day document's data
            let currentDayDocumentSnapshot = try await currentDayDocumentRef.getDocument()
            
            // Ensure that the current day's document exists before proceeding
            guard var currentDayData = currentDayDocumentSnapshot.data() else {
                print("Current day's document does not exist or contains no data.")
                return
            }
            
            // Extract only the "HabitData" from the current day data
            guard var habitData = currentDayData["HabitData"] as? [String: Any] else {
                print("No HabitData found in current day's document.")
                return
            }
            
            // Extract and modify the "isHabitStriked" map
            if var isHabitStriked = habitData["isHabitStriked"] as? [String: Bool] {
                // Set all values in "isHabitStriked" to false
                for key in isHabitStriked.keys {
                    isHabitStriked[key] = false
                }
                // Update the "HabitData" with the modified "isHabitStriked" map
                habitData["isHabitStriked"] = isHabitStriked
            } else {
                print("No isHabitStriked map found.")
            }
            
            // Prepare an empty "TaskData" structure
            let emptyTaskData: [String: Any] = [
                "tasks": [],
                "taskTimerDictionary": [:]
            ]
            
            // Calculate the day of year for the next days (nextDayInDocs is current day + 6)
            let nextDayInDocs = currentDayOfYear + 6
            
            // Iterate over the next six days to create new documents
            for i in (nextDayInDocs - dayTrackerOffset)...nextDayInDocs {
                
                // Construct the document reference for the next day
                let nextDayDocumentRef = userRef.collection("CircleData").document("\(i)")
                
                // Check if the document for the next day already exists
                let documentSnapshot = try await nextDayDocumentRef.getDocument()
                
                // If the document for the next day doesn't exist, create it
                if !documentSnapshot.exists {
                    // Create a new document with modified "HabitData" and empty "TaskData"
                    try await nextDayDocumentRef.setData([
                        "HabitData": habitData,
                        "TaskData": emptyTaskData
                    ])
                    
                    print("Created new document for day \(i) with current day's modified HabitData and empty TaskData.")
                }
            }
        } catch {
            print("Error in newCircleDoc(): \(error)")
        }
    }
    
    
    //  MARK: Add Friends
    @Published var addFriendsError = false
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
            
            if !usernameExists {
                self.addFriendsError = true
                return
            }
            
            // Fetch the current 'Friends' field
            let userDoc = try await userRef.getDocument()
            if let currentFriends = userDoc.data()?["Friends"] as? [String] {
                
                // Append the new email to the existing 'Friends' array
                if !currentFriends.contains(username) {
                    
                    // Update the 'Friends' field with the new array
                    try await userRef.updateData([
                        "Friends": FieldValue.arrayUnion([username])
                    ])
                    
                } else {
                    print("func addFriends(): User already exists")
                    return
                }
            } else {
                
                // Create a new 'Friends' array with the provided email
                try await userRef.updateData([
                    "Friends": [username]
                ])
            }
            
        } catch {
            print("func addFriends(): Error checking email existence or updating data: \(error)")
        }
    }
    
    @Published var searchResults: [String: Int] = [:]
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
    
    @Published var friendsHabitData: [String: HabitData] = [:]
    @Published var friendsTaskData: [String: TaskData] = [:]
    
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
            let circleDataRef = self.databaseRef.collection("users").document(friendId).collection("CircleData").document("\(currentDayOfYear)")
            let circleDocumentSnapshot = try await circleDataRef.getDocument()
            let circleData = circleDocumentSnapshot.data()
            
            // Fetch HabitData
            if let habitDataMap = circleData?["HabitData"] as? [String: Any] {
                let decodedHabitData = try Firestore.Decoder().decode(HabitData.self, from: habitDataMap)
                DispatchQueue.main.async {
                    self.friendsHabitData[friendUsername] = decodedHabitData
                }
            }
            
            // Fetch TaskData
            if let taskDataMap = circleData?["TaskData"] as? [String: Any] {
                let decodedTaskData = try Firestore.Decoder().decode(TaskData.self, from: taskDataMap)
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
    
    @Published var friendCount: Int = 0
    @Published var friendOrFriends: String = "Friends"
    
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
    
    
    //  MARK: SIGN OUT
    func signOut() {
        do {
            try self.authRef.signOut() // firebase sign out
            self.userSession = nil // takes us back to login screen
            clearData()
            
        } catch {
            print("SIGNED OUT Failed... \(error.localizedDescription)")
        }
    }
    
    
    //  MARK: DELETE ACCOUNT
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
    
    
    //    MARK: Authentication
    @Published var secureField: Bool = false
    
    
    //    MARK: Settings
    @Published var isSettingsVisible = false
    
    
    //    MARK: BlurView
    @Published var isBlurViewVisible: Bool = false
    @Published var isProfileBlurViewVisible: Bool = false
    @Published var isPostBlurViewVisible: Bool = false
    
    
    func weekdayMinus() {
        if currentDayOfWeek == currentDayOfYear {
            currentDayOfWeek += 6
        } else {
            currentDayOfWeek -= 1
        }
        Task {
            await listenForCircleData(dayOfYear: currentDayOfWeek)
        }
    }
    
    func weekdayPlus() {
        if currentDayOfWeek == currentDayOfYear + 6 {
            currentDayOfWeek -= 6
        } else {
            currentDayOfWeek += 1
        }
        Task {
            await listenForCircleData(dayOfYear: currentDayOfWeek)
        }
    }
    
    
    //    MARK: WeekDays
    
    @Published var weekDay: [String] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    
    // Takes day of year and the year as parameters. Then returns the weekday index
    func weekdayIndex(forDayOfYear dayOfYear: Int, inYear year: Int) -> Int? {
        // Check if the year is valid
        guard year > 0 else {
            return nil
        }
        
        // Create a Calendar instance
        let calendar = Calendar.current
        
        // Check if the day of the year is valid
        guard dayOfYear > 0 && dayOfYear <= 365 + (isLeapYear(year) ? 1 : 0) else {
            return nil
        }
        
        // Create a DateComponents instance for the given year and day of the year
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.day = dayOfYear
        
        // Get the date for the given year and day of the year
        guard let date = calendar.date(from: dateComponents) else {
            return nil
        }
        
        // Get the weekday index for the date (0 for Sunday, 1 for Monday, ..., 6 for Saturday)
        var weekdayIndex = calendar.component(.weekday, from: date) - 1
        if weekdayIndex == 0 {
            weekdayIndex = 7
        }
        
        return weekdayIndex - 1
    }
    
    
    //    MARK: Habits
    @Published var isAddHabitVisible = false
    @Published var habitIdArray: [String] = []
    @Published var habitIdName: [String: String] = [:] // Dictionary = [Habit Id : Habit Name]
    @Published var habitPositions: [String: CGSize] = [:] // Dictionary = [Habit Id : Habit coordinates]
    @Published var isHabitStriked: [String: Bool] = [:] // Dictionary = [Habit Id : Striked/ Not Striked]
    @Published var selectedHabit: String? // String that's about to be removed. '?' shows that it could be 'nil'
    @Published var habitName: String = ""
    @Published var habitTime: String = ""
    
    func habitAppender() {
        guard let userId = userSession?.uid else {
            print("func habitAppender(): User is not logged in.")
            return
        }
        
        let habitId = UUID().uuidString
        habitIdArray.append(habitId)
        habitIdName[habitId] = habitName
        isHabitStriked[habitId] = false
        
        let userRef = self.databaseRef.collection("users").document(userId)
        
        // Check if there is exactly 1 element in the `isHabitStriked` dictionary
        if isHabitStriked.count == 1 {
            // If there is only one habit, update the current day and the next 6 days
            for i in 0..<7 {
                let nextDayOfYear = currentDayOfYear + i
                let habitDataRef = userRef.collection("CircleData").document("\(nextDayOfYear)")
                
                habitDataRef.updateData([
                    "HabitData.habitIdArray": FieldValue.arrayUnion([habitId]),
                    "HabitData.habitIdName.\(habitId)": habitName,
                    "HabitData.isHabitStriked.\(habitId)": false
                ])
                
            }
        } else {
            habitDataForDay[currentDayOfWeek]?.isHabitStriked[habitId] = false
            
            let habitDataRef = userRef.collection("CircleData").document("\(currentDayOfWeek)")
            
            habitDataRef.updateData([
                "HabitData.habitIdArray": FieldValue.arrayUnion([habitId]),
                "HabitData.habitIdName.\(habitId)": habitName,
                "HabitData.isHabitStriked.\(habitId)": false
            ])
            
            for i in 1..<7 {
                let nextDayOfYear = currentDayOfYear + i
                let habitDataRef = userRef.collection("CircleData").document("\(nextDayOfYear)")
                
                habitDataRef.updateData([
                    "HabitData.habitIdArray": FieldValue.arrayUnion([habitId]),
                    "HabitData.habitIdName.\(habitId)": habitName,
                    "HabitData.isHabitStriked.\(habitId)": false
                ])
            }
        }
        
        Task {
            // Assuming `listenForUser` and `listenForHabitData` are asynchronous tasks
            await listenForUser()
            await listenForCircleData(dayOfYear: currentDayOfYear)
        }
    }
    
    
    func habitStriker(value: String) {
        guard let userId = userSession?.uid else {
            print("func habitStriker(): User is not logged in.")
            return
        }
        
        habitDataForDay[currentDayOfWeek]?.isHabitStriked[value]?.toggle()
        
        let userRef = self.databaseRef.collection("users").document(userId)
        let habitDataRef = userRef.collection("CircleData").document("\(currentDayOfWeek)")
        
        habitDataRef.updateData([
            "HabitData.isHabitStriked": habitDataForDay[currentDayOfWeek]?.isHabitStriked
        ])
        
        Task {
            await listenForUser()
            await listenForCircleData(dayOfYear: currentDayOfWeek)
        }
        
        self.habitData = habitDataForDay[currentDayOfWeek] // Trigger a re-render by reassigning the object
    }
    
    @Published var offsetX: CGFloat = 0
    func habitRemover(value: String) {
        guard let userId = userSession?.uid else {
            return
        }
        
        if var currentHabitData = self.habitDataForDay[self.currentDayOfWeek] {
            
            currentHabitData.habitIdArray.removeAll { $0 == value }
            currentHabitData.habitIdName.removeValue(forKey: value)
            currentHabitData.isHabitStriked.removeValue(forKey: value)
            
            self.habitDataForDay[self.currentDayOfWeek] = currentHabitData
        }
        
        let circleDocRef = self.databaseRef.collection("users").document(userId).collection("CircleData").document(String(self.currentDayOfWeek))
        circleDocRef.updateData([
            "HabitData.habitIdArray": FieldValue.arrayRemove([value]),
            "HabitData.habitIdName.\(value)": FieldValue.delete(),
            "HabitData.isHabitStriked.\(value)": FieldValue.delete()
        ]) { error in
            if let error = error {
                print("func habitRemover(): Error updating document: \(error)")
            }
        }
    }
    
    
    //    MARK: Task DropDown Menu
    @Published var taskString: String = ""
    @Published var tasks: [String] = [] {
        didSet {
            newTimeCalc()
        }
    }
    @Published var progressTasks: [String] = [] {
        didSet {
            newTimeCalc()
        }
    }
    let maxTime = 100
    
    func taskAdder() async {
        guard let userId = self.authRef.currentUser?.uid else {
            print("func taskAdder(): User is not logged in")
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(userId)
        
        do {
            let document = try await userRef.getDocument()
            
            // Fetch progress data
            let progressData = document.data()?["Progress"] as? [String: Any] ?? [:]
            var currentTasks = progressData["progressTasks"] as? [String] ?? []
            
            // Update progress data
            currentTasks.append(self.taskString)
            
            // Update database
            do {
                try await userRef.updateData([
                    "Progress.progressTasks": currentTasks
                ])
                
                DispatchQueue.main.async {
                    self.progressTasks = currentTasks
                }
                
            } catch {
                print("func taskAdder(): error updating userRef: \(error.localizedDescription)")
            }
            
            // Fetch and update CircleData
            let circleDataRef = userRef.collection("CircleData").document(String(self.currentDayOfYear))
            
            do {
                let document = try await circleDataRef.getDocument()
                
                // Fetch task data
                var taskData = document.data()?["TaskData"] as? [String: Any] ?? [:]
                var currentTasks = taskData["tasks"] as? [String] ?? []
                
                // Update task data
                currentTasks.append(self.taskString)
                
                // Update database
                do {
                    try await circleDataRef.updateData([
                        "TaskData.tasks": currentTasks
                    ])
                    
                    DispatchQueue.main.async {
                        self.taskString = "" // Clear the task input field after successful addition
                    }
                } catch {
                    print("func taskAdder(): error updating circleDataRef: \(error.localizedDescription)")
                }
                
            } catch {
                print("func taskAdder(): error fetching CircleData doc: \(error.localizedDescription)")
                return
            }
            
        } catch {
            print("func taskAdder(): error fetching user doc: \(error.localizedDescription)")
            return
        }
    }
    
    func newTaskAdder(task: String) async {
        guard let userId = self.authRef.currentUser?.uid else {
            return
        }
        
        let circleDataRef = self.databaseRef.collection("users").document(userId).collection("CircleData").document("\(self.currentDayOfYear)")
        
        do {
            let document = try await circleDataRef.getDocument()
            
            if let taskData = document.data()?["TaskData"] as? [String: Any],
               let tasks = taskData["tasks"] as? [String] {
                
                // Check if the task is not already in the array
                if !tasks.contains(task) {
                    
                    do {
                        try await circleDataRef.updateData([
                            "TaskData.tasks": FieldValue.arrayUnion([task]) //adds 'task' without replacing array
                        ])
                    } catch {
                        print("func newTaskAdder(): failed to update data: \(error.localizedDescription)")
                    }
                    
                }
                
            } else {
                print("func newTaskAdder(): TaskData doesn't exist")
            }
            
        } catch {
            print("func newTaskAdder(): Document doesn't exist")
        }
    }
    
    
    
    @Published var taskMaxTime: [String: Int] = [:] // Dictionary = [Task Title: Max Time]
    @Published var maxTimeAlert: Bool = false
    
    @Published var isAddTaskVisible = false
    @Published var isTaskDropDownVisible = false
    
    @Published var taskDecimalDict: [String: Double] = [:] {
        didSet {
            newTimeCalc()
        }
    } // Dictionary = [Task Title: fraction of task completed]
    @Published var taskPercentageDict: [String: Int] = [:] // Dictionary = [Task Title: percentage of task completed]
    func progressPercentage() {
        guard let userId = userSession?.uid else {
            print("func ProgressPercentage(): User is not logged in.")
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(userId)
        var maxTimeIncreasedTasks: [String: Int] = [:]
        
        for item in progressTasks {
            // Ensure task time does not exceed max time
            if let currentTime = progressTimerDictionary[item] {
                let currentMaxTime = taskMaxTime[item] ?? maxTime
                if currentTime >= currentMaxTime {
                    let newMaxTime = ((currentTime / 100) + 1) * 100
                    progressTimerDictionary[item] = newMaxTime
                    newTimeCalc()
                    maxTimeAlert.toggle()
                    maxTimeIncreasedTasks[item] = newMaxTime
                }
            }
        }
        
        for (task, newMaxTime) in maxTimeIncreasedTasks {
            taskMaxTime[task] = newMaxTime
            userRef.updateData([
                "Progress.taskMaxTime.\(task)" : newMaxTime
            ])
        }
        
        self.updateTaskProgress(userId: userId)
    }
    
    private func updateTaskProgress(userId: String) {
        // Update ProgressData
        let userRef = self.databaseRef.collection("users").document(userId)
        
        for item in progressTasks {
            let decimal = Double(progressTimerDictionary[item] ?? 0) / Double(taskMaxTime[item] ?? maxTime)
            taskDecimalDict[item] = decimal
        }
        
        userRef.updateData([
            "Progress.taskDecimalDict": taskDecimalDict
        ])
        
        Task {
            await listenForUser()
        }
    }
    
    func updateTaskDecimalDict() {
        for item in progressTimerDictionary.keys {
            let decimal = Double(progressTimerDictionary[item] ?? 0) / Double(taskMaxTime[item] ?? maxTime)
            taskDecimalDict[item] = decimal
        }
        
        guard let userId = userSession?.uid else {
            print("User is not logged in.")
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(userId)
        
        userRef.updateData([
            "Progress.taskDecimalDict": self.taskDecimalDict
        ]) { error in
            if let error = error {
                print("Error updating taskDecimalDict: \(error.localizedDescription)")
            } else {
                print("taskDecimalDict successfully updated in Firestore.")
            }
        }
    }
    
    
    @Published var maxWidth: Double = 340
    @Published var newTimeArray: [String: Int] = [:]
    
    func newTimeCalc() {
        for item in progressTasks {
            let newTime = (maxWidth * (taskDecimalDict[item] ?? 0))
            newTimeArray[item] = Int(newTime)
        }
    }
    
    
    //    MARK: Task Timer
    @Published var isTimerOn: Bool = false
    @Published var timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect() // Just initializing 'timer' variable
    @Published var progressTimerDictionary: [String: Int] = [:] // Dictionary = [Task Title : cumulative TimerCount for task]
    @Published var taskTimerDictionary: [String: Int] = [:] // Dictionary = [Task Title : Timer count for task]
    @Published var taskName = "Task"
    @Published var taskTime: Int = 0 {
        didSet {
            formattedTaskTime = formatTime(taskTime)
        }
    }
    
    @Published var timerCount: Int = 0
    @Published var formattedTaskTime: String = "00:00:00"
    
    func formatTime(_ time: Int) -> String {
        let hours = time / 3600
        let minutes = (time % 3600) / 60
        let seconds = time % 60
        
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    func taskTimer() -> Int? {
        for item in progressTasks {
            if item == taskName {
                
                let existingProgressCount = progressTimerDictionary[item] ?? 0
                let progressCount = existingProgressCount + 1
                
                let timerCount = (taskTimerDictionary[item] ?? 0) + 1
                
                // Update dictionaries with the new progress
                progressTimerDictionary[item] = progressCount
                taskTimerDictionary[item] = timerCount
                
                // Update the Firestore documents
                updateTaskTimerInFirestore(taskName: item, progressCount: progressCount, timerCount: timerCount)
                
                // Update cumulative tasks in Firestore periodically
                Task {
                    await listenForUser()
                    updateCumulativeProgressPeriodically()
                }
                
                return timerCount
            }
        }
        return nil
    }
    
    @Published var formattedCumulativeTime: String = "00:00:00"
    @Published var cumulativeTime: Int = 0 {
        didSet {
            formattedCumulativeTime = formatTime(cumulativeTime)
        }
    }
    /// This function updates the cumulative progress periodically (e.g., every second)
    func updateCumulativeProgressPeriodically() {
        // Throttle the updates to avoid overloading Firestore
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            self.cumulativeProgress()  // Recalculate cumulative progress
            
            DispatchQueue.main.async {
                self.cumulativeTime = self.cumulativeProg
            }
        }
    }
    
    func updateTaskTimerInFirestore(taskName: String, progressCount: Int, timerCount: Int) {
        guard let userId = userSession?.uid else {
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(userId)
        userRef.updateData([
            "Progress.progressTimerDictionary.\(taskName)": progressCount
        ])
        
        let circleDataRef = userRef.collection("CircleData").document(String(self.currentDayOfYear))
        circleDataRef.updateData([
            "TaskData.taskTimerDictionary.\(taskName)": timerCount
        ])
        
        Task {
            await listenForUser()
        }
    }
    
    func resetTimer() -> Int? {
        for item in progressTasks {
            if item == taskName {
                if taskTimerDictionary[item] == nil {
                    return 0
                } else {
                    return taskTimerDictionary[item]
                }
            }
        }
        return nil
    }
    
    
    //    MARK: Circles
    @Published var selectedChartPosition: Int?
    @Published var taskSectorRange: [String: Range<Int>] = [:]
    
    func colorReturn(value: String) -> Color {
        if habitData?.isHabitStriked[value] == true {
            return .blue
        } else {
            return .gray
        }
    }
    
    
    //    MARK: View Your Progress
    @Published var isViewYourProgressVisible = false
    
    @Published var docTitles: [Int?] = []
    func fetchCircleDocRef() async {
        // Ensure the user is logged in
        guard let currentUserId = self.authRef.currentUser?.uid else {
            print("func fetchCircleDocRef(): User not logged in.")
            return
        }
        
        do {
            let circleDataRef = self.databaseRef.collection("users").document(currentUserId).collection("CircleData")
            
            for dayOffset in 1..<11 {
                let dayToCollect = String(currentDayOfYear - dayOffset)
                
                // Create a query to fetch documents with the specific dayToCollect as the document ID
                let query = circleDataRef.document(dayToCollect)
                let documentSnapshot = try await query.getDocument()
                
                if let documentData = documentSnapshot.data() {
                    // Document exists, handle the data
                    docTitles.append(Int(dayToCollect))
                }
            }
        } catch {
            print("func fetchCircleDocRef(): Error fetching HabitData document: \(error.localizedDescription)")
        }
    }
    
    
    //    MARK: Calendar
    func dayOfYear(year: Int, month: Int, day: Int) -> Int {
        // Define the number of days in each month
        let daysInMonth: [Int] = [31, 28 + (year % 4 == 0 ? (year % 100 != 0 || year % 400 == 0 ? 1 : 0) : 0), 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        
        // Calculate the day of the year
        var dayOfYear = day
        for i in 0..<month - 1 {
            dayOfYear += daysInMonth[i]
        }
        return dayOfYear
    }
    
    func isLeapYear(_ year: Int) -> Bool {
        return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
    }
    
    func dateFromDayOfYear(index: Int, year: Int, dayOfYear: Int) -> (month: Int, day: Int)? {
        // Define the number of days in each month
        let daysInMonth: [Int] = [31, isLeapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        
        // Validate dayOfYear
        let totalDaysInYear = isLeapYear(year) ? 366 : 365
        guard dayOfYear >= 1 && dayOfYear <= totalDaysInYear else {
            print("Invalid dayOfYear: \(dayOfYear)")
            return nil
        }
        
        var remainingDays = dayOfYear
        var month = 1
        
        // Iterate through the months to find the corresponding month and day
        for days in daysInMonth {
            if remainingDays <= days {
                return (month, remainingDays)
            }
            remainingDays -= days
            month += 1
        }
        
        print("func dateFromDayOfYear(): Should never reach this point if input is valid")
        return nil // This should never be reached if the input is valid
    }
    
    
    @Published var dictionaryCount: Int = 0
    @Published var habitDataForDay: [Int: Prod1.HabitData] = [:] // Dictionary = [Day of year: habit data]
    @Published var taskDataForDay: [Int: Prod1.TaskData] = [:] // Dictionary = [Day of year: task data]
    func listenForCircleData(dayOfYear: Int) async {
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        // Reference to users document in Firestore
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        // Reference to dayOfYear document in habitData sub-collection
        let circleDataRef = userRef.collection("CircleData").document(String(dayOfYear))
        
        // Add a snapshot listener to listen for changes in the dayOfYear document
        circleDataRef.addSnapshotListener { documentSnapshot, error in
            // Check if data exists
            guard let circleDocument = documentSnapshot else {
                print("Error fetching HabitData: \(error!)")
                return
            }
            // Check if document exists
            guard circleDocument.exists else {
                return
            }
            
            // extract data from dayOfYear document
            if let circleData = circleDocument.data() {
                
                // Fetch and decode habit data
                if let habitData = circleData["HabitData"] as? [String: Any] {
                    do {
                        // Decode habit data into custom data model
                        let decodedHabitData = try Firestore.Decoder().decode(Prod1.HabitData.self, from: habitData)
                        // Update habitDataForDay dictionary with the fetched habit data
                        self.habitDataForDay[dayOfYear] = decodedHabitData
                    } catch {
                        print("Error decoding HabitData for day \(dayOfYear): \(error.localizedDescription)")
                    }
                }
                
                // Fetch and decode task data
                if let taskData = circleData["TaskData"] as? [String: Any] {
                    do {
                        let decodedTaskData = try Firestore.Decoder().decode(Prod1.TaskData.self, from: taskData)
                        self.taskDataForDay[dayOfYear] = decodedTaskData
                    } catch {
                        print("Error decoding TaskData: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    //    MARK: ADD FRIENDS
    @Published var isFriendsVisible: Bool = false
    @Published var isAddFriendsVisible: Bool = false
    
    //    MARK: CUSTOM COLOURS
    @Published var darkGray: Color = Color(.sRGB, red: 0.1, green: 0.1, blue: 0.1, opacity: 1.0)
    
    //    MARK: COMING SOON...
    @Published var comingSoonAlert: Bool = false
    
    //    MARK: IMAGE POST
    @Published var showImagePicker: Bool = false
    @Published var libraryIsVisible: Bool = false
    @Published var capturedImage: UIImage?
    @Published var selectedImage: UIImage?
    @Published var caption: String = ""
    @Published var backButton: Bool = false
    var username: String = ""
    
    
    func fetchUsername(for userId: String) async throws -> String {
        let userRef = databaseRef.collection("users").document(userId)
        let document = try await userRef.getDocument()
        if let authData = document.data()?["AuthenticationData"] as? [String: Any],
           let username = authData["username"] as? String {
            return username
        } else {
            throw NSError(domain: "uploadComment", code: 404, userInfo: [NSLocalizedDescriptionKey: "Username not found"])
        }
    }
    
    
    @Published var habitDataForDayTimeline: [String: Prod1.HabitData] = [:] // Dictionary = [Day of year: habit data]
    func listenForTimelineHabitData(id: String, userId: String, dayOfYear: Int) async {
        
        let userRef = self.databaseRef.collection("users").document(userId)
        
        // Reference to dayOfYear document in habitData sub-collection
        let habitDataRef = userRef.collection("HabitData").document(String(dayOfYear))
        
        // Add a snapshot listener to listen for changes in the dayOfYear document
        do {
            let habitDocument = try await habitDataRef.getDocument()
            
            // extract data from dayOfYear document
            if let habitData = habitDocument.data() {
                do {
                    // Decode habit data into custom data model
                    let decodedHabitData = try Firestore.Decoder().decode(Prod1.HabitData.self, from: habitData)
                    
                    // Update habitDataForDay dictionary with the fetched habit data
                    self.habitDataForDayTimeline[id] = decodedHabitData
                    
                } catch {
                    print("func listenForTimelineHabitData(): Error decoding HabitData for day \(dayOfYear): \(error.localizedDescription)")
                }
            }
        } catch {
            print("func listenForTimelineHabitData(): Error fetching HabitData: \(error.localizedDescription)")
            return
        }
    }
    
    @Published var isProfileViewVisible: Bool = false
    
    @Published var cumulativeProg: Int = 0
    @Published var cumulativeTasks: [String: Int] = [:]
    func cumulativeProgress() {
        guard let currentUserId = userSession?.uid else {
            print("func cumulativeProgress(): User session not available")
            return
        }
        
        // Step 1: Get the current date and the current month range in terms of day of the year
        let calendar = Calendar.current
        let currentDate = Date()
        
        // Get the first and last day of the current month
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate))!
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        
        // Get the day of the year for the start and end of the month
        let startDayOfYear = calendar.ordinality(of: .day, in: .year, for: startOfMonth)!
        let endDayOfYear = calendar.ordinality(of: .day, in: .year, for: endOfMonth)!
        
        // Step 2: Reference the "CircleData" sub-collection
        let circleDataRef = self.databaseRef.collection("users").document(currentUserId).collection("CircleData")
        
        // Step 3: Fetch all documents from the "CircleData" sub-collection
        circleDataRef.getDocuments { (querySnapshot, error) in
            if let error = error {
                print("func cumulativeProgress(): Error fetching CircleData - \(error)")
                return
            }
            
            // Step 4: Initialize a variable to store the cumulative sum
            var totalCumulativeProgress = 0
            
            // Step 5: Iterate over each document in the "CircleData" sub-collection
            guard let documents = querySnapshot?.documents else {
                print("func cumulativeProgress(): No documents found in CircleData")
                return
            }
            
            for document in documents {
                // The document ID is the day of the year, so convert it to an Int
                if let dayOfYear = Int(document.documentID), dayOfYear >= startDayOfYear, dayOfYear <= endDayOfYear {
                    // Step 6: Extract the "TaskData" map from each document within the date range
                    let data = document.data()
                    
                    if let taskData = data["TaskData"] as? [String: Any],
                       let taskTimerDictionary = taskData["taskTimerDictionary"] as? [String: Int] {
                        
                        // Step 7: Sum the values in taskTimerDictionary and add them to the total
                        let documentTotal = taskTimerDictionary.values.reduce(0, +)
                        totalCumulativeProgress += documentTotal
                    } else {
                        print("func cumulativeProgress(): TaskData or taskTimerDictionary not found in document \(document.documentID)")
                    }
                }
            }
            
            // Step 8: Update the @Published var with the total cumulative progress
            self.cumulativeProg = totalCumulativeProgress
            self.updateCumulativeTasks()
        }
    }
    
    func updateCumulativeTasks() {
        guard let currentUserId = userSession?.uid else {
            print("func updateCumulativeTasks(): User session not available")
            return
        }
        
        // Step 1: Get the current month as a string
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM" // This will give us the full month name, e.g., "September"
        let currentMonth = dateFormatter.string(from: Date())
        
        // Step 2: Reference the user document
        let userDocRef = self.databaseRef.collection("users").document(currentUserId)
        
        // Step 3: Fetch the existing "Analytics" document
        userDocRef.getDocument { document, error in
            if let error = error {
                print("func updateCumulativeTasks(): Error fetching Analytics document - \(error)")
                return
            }
            
            guard let document = document, document.exists, var userData = document.data() else {
                print("func updateCumulativeTasks(): Analytics document does not exist or data is nil")
                return
            }
            
            // Step 4: Check if the "cumulativeTasks" map exists, otherwise create a new one
            let analyticsData = userData["Analytics"] as? [String: Any]
            var cumulativeTasks = analyticsData?["cumulativeTasks"] as? [String: Int] ?? [:]
            
            // Step 5: Update the map with the current month and cumulative progress
            self.cumulativeTasks[currentMonth] = self.cumulativeProg
            
            // Step 6: Write the updated map back to the "Analytics" document
            userDocRef.updateData([
                "Analytics.cumulativeTasks": self.cumulativeTasks
            ]) { error in
                if let error = error {
                    print("func updateCumulativeTasks(): Error updating cumulativeTasks - \(error)")
                }
            }
        }
    }
    
    @Published var taskSum: Int = 0
    func taskTimerDictionarySum(dayOfYear: Int) {
        guard let currentUserId = userSession?.uid else {
            return
        }
        
        self.taskSum = 0
        
        let CircleDataRef = self.databaseRef.collection("users").document(currentUserId).collection("CircleData").document(String(dayOfYear))
        
        // Fetch the document for the given dayOfYear
        CircleDataRef.getDocument { document, error in
            if let error = error {
                print("Error fetching document: \(error)")
                return
            }
            
            // Check if the document exists and contains data
            guard let document = document, document.exists, let data = document.data() else {
                return
            }
            
            // Extract the "taskTimerDictionary" from the document data
            
            if let taskData = data["TaskData"] as? [String: Any],
               let taskTimerDictionary = taskData["taskTimerDictionary"] as? [String: Int] {
                // Calculate the sum of all values in taskTimerDictionary
                let total = taskTimerDictionary.values.reduce(0, +)
                
                // Update the published variable on the main thread
                DispatchQueue.main.async {
                    self.taskSum = total
                }
            }
        }
    }
    
    @Published var selectedItem: PhotosPickerItem? {
        didSet {
            Task {
                if let selectedItem {
                    if let imageData = try? await selectedItem.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: imageData) {
                        DispatchQueue.main.async {
                            self.profileImage = Image(uiImage: uiImage)
                        }
                    }
                }
                try await saveImage()
                retrieveImage()
            }
        }
    }
    
    @Published var profileImage: Image?
    
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
    
    @Published var profileImageCache: [String: Image] = [:]

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
    
    @Published var placeholderTasks: [Int] = [1]
}

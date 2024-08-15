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
    }
    
    
//  MARK: Listen For Data
    func listenForUser() async {
        // Checks if User is logged in
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        // Add a listener for changes to the user document
        let userRef = self.databaseRef.collection("users").document(currentUserId)
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
                
                dayTrackerMath()
                if dayConstant < currentDayOfYear {
                    await newCircleDoc()
                }
            }
            
            await fetchCircleDocRef()
            
        } catch {
            logInError.toggle()
            print("LOG IN Failed... \(error.localizedDescription)")
        }
    }
    
    @Published var dayTracker: [Int] = []
    @Published var dayTrackerOffset: Int = 0
    private func dayTrackerMath() {
        // Checks if User is logged in
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        // Reference to the specific user document
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        
        // Fetch the current 'dayTracker' array from Firestore
        userRef.getDocument { (document, error) in
            if let document = document, document.exists {
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
                
                Task {
                    await self.analyticsUpdate()
                }
            } else {
                print("Document does not exist")
            }
        }
    }
    
    
//  MARK: SIGN UP
    @Published var signUpError: Bool = false
    func signUp(withEmail email: String, password: String, username: String) async throws {
        do {
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
            
            // Store user data
            let user = UserObject(id: result.user.uid,
                                  username: username,
                                  email: email) // initializes the raw data for encoding
            let encodedUser = try Firestore.Encoder().encode(user) // encodes raw data to encrypted data
            let userRef = self.databaseRef.collection("users").document(user.id)
            try await userRef.setData(["AuthenticationData": encodedUser])
            
            let analytics = Prod1.Analytics(dayTracker: dayTracker,
                                            dayTrackerOffset: dayTrackerOffset)
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
            
            clearData()
            Task {
                await listenForUser()
                await listenForCircleData(dayOfYear: currentDayOfWeek)
            }
            
            await fetchCircleDocRef()
            dayConstant = currentDayOfYear
            dayTracker.append(currentDayOfYear)
            await analyticsUpdate()
            
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
            "dayTrackerOffset": self.dayTrackerOffset
        ]
        try await userRef.updateData([
            "Analytics": analyticsUpdate
        ]) { err in
            if let err = err {
                print("Error updating document: \(err)")
            }
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

        // Calculate the day of year for the current day plus 'i'
        let nextDayInDocs = currentDayOfYear + 6
        
        // Iterate over the next six days
        for i in (nextDayInDocs - dayTrackerOffset)...nextDayInDocs {
            
            // Construct the document reference for the current day
            let currentDayDocumentRef = userRef.collection("CircleData").document("\(i)")

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
                print("func newCircleDoc(): Error checking or updating HabitData for day \(i): \(error)")
            }
        }
    }
    
    
//  MARK: Add Friends
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
                print("Email does not exist in the database.")
                return
            }
            
            // Fetch the current 'Friends' field
            let userDocument = try await userRef.getDocument()
            if var currentFriends = userDocument.data()?["Friends"] as? [String] {
                // Append the new email to the existing 'Friends' array
                if !currentFriends.contains(username) {
                    currentFriends.append(username)
                } else {
                    print("Email already exists in the Friends array.")
                    return
                }
                
                // Update the 'Friends' field with the new array
                try await userRef.updateData(["Friends": currentFriends])
            } else {
                // Create a new 'Friends' array with the provided email
                let newFriends = [username]
                try await userRef.setData(["Friends": newFriends], merge: true)
            }
            
        } catch {
            print("Error checking email existence or updating data: \(error)")
        }
    }
    
    func fetchAllFriendsData() async {
        // Checks if User is logged in
        guard let currentUserId = self.authRef.currentUser?.uid else {
            print("User not logged in.")
            return
        }

        let userRef = self.databaseRef.collection("users").document(currentUserId)

        do {
            let documentSnapshot = try await userRef.getDocument()
            guard let documentData = documentSnapshot.data(), let friends = documentData["Friends"] as? [String] else {
                return
            }

            // Fetch habit data for all friends
            for friendUsername in friends {
                await fetchFriendData(friendUsername: friendUsername)
            }
        } catch {
            print("Error fetching user document: \(error.localizedDescription)")
        }
    }
    
    @Published var friendsHabitData: [String: HabitData] = [:]
    @Published var friendsTaskData: [String: TaskData] = [:]

    func fetchFriendData(friendUsername: String) async {
        let query = self.databaseRef.collection("users").whereField("AuthenticationData.username", isEqualTo: friendUsername)

        do {
            let querySnapshot = try await query.getDocuments()
            guard let friendDoc = querySnapshot.documents.first else {
                print("Friend with username \(friendUsername) not found.")
                return
            }

            let friendId = friendDoc.documentID

            // Fetch HabitData
            let habitDataRef = self.databaseRef.collection("users").document(friendId).collection("CircleData").document("\(currentDayOfYear)")
            let habitDocumentSnapshot = try await habitDataRef.getDocument()
            guard let habitData = habitDocumentSnapshot.data() else {
                print("No HabitData found for friend with username \(friendUsername).")
                return
            }
            let decodedHabitData = try Firestore.Decoder().decode(HabitData.self, from: habitData)
            DispatchQueue.main.async {
                self.friendsHabitData[friendUsername] = decodedHabitData
            }

            // Fetch TaskData
            if let taskDataMap = friendDoc.data()["TaskData"] as? [String: Any] {
                let jsonData = try JSONSerialization.data(withJSONObject: taskDataMap, options: [])
                let decodedTaskData = try JSONDecoder().decode(TaskData.self, from: jsonData)
                DispatchQueue.main.async {
                    self.friendsTaskData[friendUsername] = decodedTaskData
                }
            } else {
                print("No TaskData found for friend with username \(friendUsername).")
            }

        } catch {
            print("Error fetching friend's data: \(error.localizedDescription)")
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
            guard let documentData = documentSnapshot.data(), let friends = documentData["Friends"] as? [String] else {
                return
            }

            // Return the count of elements in the 'Friends' array
            friendCount = friends.count
            await friendOrFriends(friendCount: friends.count)
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
        let habitId = UUID().uuidString
        habitIdArray.append(habitId)
        habitIdName[habitId] = habitName
        isHabitStriked[habitId] = false
        
        if let userId = userSession?.uid {
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
            
            // Assuming `listenForUser` and `listenForHabitData` are asynchronous tasks
            Task {
                await listenForUser()
                await listenForCircleData(dayOfYear: currentDayOfYear)
            }
        }
    }


    func habitStriker(value: String) {
        habitDataForDay[currentDayOfWeek]?.isHabitStriked[value]?.toggle()
        if let userId = userSession?.uid {
            let userRef = self.databaseRef.collection("users").document(userId)
            let habitDataRef = userRef.collection("CircleData").document("\(currentDayOfWeek)")
            habitDataRef.updateData(["HabitData.isHabitStriked": habitDataForDay[currentDayOfWeek]?.isHabitStriked])
            
            Task {
                await listenForUser()
                await listenForCircleData(dayOfYear: currentDayOfWeek)
                self.habitData = habitDataForDay[currentDayOfWeek] // Trigger a re-render by reassigning the object
            }
        } else {
            print("User is not logged in.")
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
    
    func taskAdder() {
        guard let userId = self.authRef.currentUser?.uid else {
            print("func taskAdder(): User is not logged in")
            return
        }

        let userRef = self.databaseRef.collection("users").document(userId)

        // Fetch and update ProgressData
        userRef.getDocument { document, error in
            if let error = error {
                print("func taskAdder(): error fetching user doc: \(error.localizedDescription)")
                return
            }

            // Fetch progress data
            var progressData = document?.data()?["Progress"] as? [String: Any] ?? [:]
            var currentTasks = progressData["progressTasks"] as? [String] ?? []

            // Update progress data
            currentTasks.append(self.taskString)

            // Update database
            userRef.updateData([
                "Progress.progressTasks": currentTasks
            ]) { error in
                if let error = error {
                    print("func taskAdder(): error updating userRef: \(error.localizedDescription)")
                } else {
                    DispatchQueue.main.async {
                        self.progressTasks = currentTasks
                    }
                }
            }
            
            // Fetch and update CircleData
            let circleDataRef = userRef.collection("CircleData").document(String(self.currentDayOfYear))
            circleDataRef.getDocument { document, error in
                if let error = error {
                    print("func taskAdder(): error fetching CircleData doc: \(error.localizedDescription)")
                    return
                }

                // Fetch task data
                var taskData = document?.data()?["TaskData"] as? [String: Any] ?? [:]
                var currentTasks = taskData["tasks"] as? [String] ?? []

                // Update task data
                currentTasks.append(self.taskString)
                taskData["tasks"] = currentTasks

                // Update database
                circleDataRef.updateData([
                    "TaskData.tasks": currentTasks
                ]) { error in
                    if let error = error {
                        print("func taskAdder(): error updating circleDataRef: \(error.localizedDescription)")
                    } else {
                        DispatchQueue.main.async {
                            self.progressTasks = currentTasks
                            self.taskString = "" // Clear the task input field after successful addition
                        }
                    }
                }
            }
        }
    }
    
    func newTaskAdder(task: String) {
        guard let userId = self.authRef.currentUser?.uid else {
            return
        }
        
        let circleDataRef = self.databaseRef.collection("users").document(userId).collection("CircleData").document("\(self.currentDayOfYear)")
        
        circleDataRef.getDocument { document, error in
            if let document = document, document.exists {
                if let taskData = document.data()?["TaskData"] as? [String: Any],
                   let tasks = taskData["tasks"] as? [String] {
                    
                    // Check if the task is not already in the array
                    if !tasks.contains(task) {
                        circleDataRef.updateData([
                            "TaskData.tasks": FieldValue.arrayUnion([task]) //adds 'task' without replacing array
                        ]) { error in
                            if let error = error {
                                print("func newTaskAdder(): failed to update data: \(error.localizedDescription)")
                            }
                        }
                    }
                } else {
                    print("func newTaskAdder(): TaskData doesn't exist")
                }
            } else {
                print("func newTaskAdder(): Document doesn't exist")
            }
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

            // Update Firestore
            var updates: [String: Any] = [:]

            for (task, newMaxTime) in maxTimeIncreasedTasks {
                taskMaxTime[task] = newMaxTime
                updates["Progress.taskMaxTime.\(task)"] = newMaxTime
            }

            userRef.updateData(updates) { error in
                if let error = error {
                    print("func ProgressPercentage(): error updating task max time: \(error.localizedDescription)")
                } else {
                    self.updateTaskProgress(userId: userId)
                }
            }
        }

        private func updateTaskProgress(userId: String) {
            for item in progressTasks {
                let decimal = Double(progressTimerDictionary[item] ?? 0) / Double(taskMaxTime[item] ?? maxTime)
                taskDecimalDict[item] = decimal
            }
            
            // Update ProgressData
            let userRef = self.databaseRef.collection("users").document(userId)
            userRef.updateData([
                "Progress.taskDecimalDict": taskDecimalDict
            ]) { error in
                if let error = error {
                    print("Error updating progress data: \(error.localizedDescription)")
                }
            }

            Task {
                await listenForUser()
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
                if var progressCount = progressTimerDictionary[item],
                    var timerCount = taskTimerDictionary[item] {
                        print("func taskTimer(): running if statement")
                        progressCount += 1
                        timerCount += 1
                        
                        progressTimerDictionary[item] = progressCount
                        taskTimerDictionary[item] = timerCount
                        
                        // Update the TaskTimerDictionary in Firestore
                        updateTaskTimerInFirestore(taskName: item, progressCount: progressCount, timerCount: timerCount)
                        Task {
                            await listenForUser()
                        }
                    
                        print("func taskTimer(): if finished")
                        return timerCount
                    } else {
                        print("func taskTimer(): running else statement")
                        let progressCount = 1
                        let timerCount = 1
                        
                        progressTimerDictionary[item] = progressCount
                        taskTimerDictionary[item] = timerCount
                        
                        // Update the TaskTimerDictionary in Firestore
                        updateTaskTimerInFirestore(taskName: item, progressCount: progressCount, timerCount: timerCount)
                        Task {
                            await listenForUser()
                        }
                        
                        print("func taskTimer(): else finished")
                        return timerCount
                    }
            }
        }
        return nil
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
            if (item == taskName) {
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

        let circleDataRef = self.databaseRef.collection("users").document(currentUserId).collection("CircleData")

        do {
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
        
        print("Error: Should never reach this point if input is valid")
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
    @Published var darkGray: Color = Color(.sRGB, red: 0.2, green: 0.2, blue: 0.2, opacity: 1.0)
    
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
    func uploadPhoto() async {
        //MARK: userId
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        //MARK: ID
        let id = UUID().uuidString
        
        // MARK: Image
        // Check selectedImage isn't nil
        guard selectedImage != nil else {
            return
        }
        
        // turn Image into Data
        let imageData = selectedImage!.jpegData(compressionQuality: 0.8)
        
        // Check if we were able to convert it
        guard imageData != nil else {
            return
        }
        
        // Specify file path and name
        let path = "images/\(UUID().uuidString).jpg"
        let fileRef = self.storageRef.child(path)
        
        
        // MARK: Timestamp
        let timestamp = Timestamp(date: Date())
        
        
        // MARK: Username
        let userRef = databaseRef.collection("users").document(currentUserId ?? "")
        userRef.getDocument { document, error in
            if let document = document, document.exists { // if doc != nil, doc exists
                if let data = document.data(),
                   let authData = data["AuthenticationData"] as? [String: Any],
                   let username = authData["username"] as? String {
                    self.username = username
                } else {
                    print("func uploadPhoto(): user doc data doesnt exist")
                }
            } else {
                print("func uploadPhoto(): user document doesnt exist")
            }
        }
        
        // Upload Data
        let uploadTask = fileRef.putData(imageData!, metadata: nil) {
            metadata, error in
            
            // check for errors
            if error == nil && metadata != nil {
                
                // Save a reference to the file in firestore Database
                self.databaseRef.collection("timeline").document().setData([
                    "id": id,
                    "userId": currentUserId,
                    "dayOfYear": self.currentDayOfYear,
                    "url": path,
                    "timestamp": timestamp,
                    "username": self.username,
                    "caption": self.caption,
                    "likeCount": 0,
                    "likes": [:],
                    "CommentsData": self.commentMap]) { error in
                    
                    // if there were no errors, display the image
                    if error == nil {
                        // add uploaded image to list of images for display
                        DispatchQueue.main.async {
                            self.postMap.append(PostData(id: id, userId: currentUserId, dayOfYear: self.currentDayOfYear, image: self.selectedImage!, timestamp: timestamp, username: self.username, caption: self.caption, likeCount: 0, likes: [:], commentsData: self.commentMap))
                            
                            Task {
                                await self.savePosts()
                            }
                        }
                    }
                }
            }
        }
    }
    
    @Published var postCommentsId: String = ""
    @Published var comment: String = ""
    @Published var commentMap = [CommentsData]()
    @Published var postMap = [PostData]()

    func uploadComment() async {
        guard let currentUserId = authRef.currentUser?.uid else {
            return
        }

        let id = UUID().uuidString
        let timestamp = Timestamp(date: Date())

        // Fetch username asynchronously
        await fetchUsername(for: currentUserId) { [weak self] username in
            guard let self = self, let username = username else {
                print("func uploadComment(): Failed to fetch username")
                return
            }

            // Find post ID and create comments sub-collection
            self.databaseRef.collection("timeline")
                .whereField("id", isEqualTo: self.postCommentsId)
                .getDocuments { [weak self] querySnapshot, error in
                    if let error = error {
                        print("func uploadComment(): Error querying post ID: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let document = querySnapshot?.documents.first else {
                        print("func uploadComment(): Document not found")
                        return
                    }

                    let documentId = document.documentID
                    let postRef = self?.databaseRef.collection("timeline").document(documentId)
                    
                    postRef?.collection("Comments").document(id).setData([
                        "id": id,
                        "userId": currentUserId,
                        "timestamp": timestamp,
                        "username": username,
                        "comment": self?.comment ?? ""
                    ]) { error in
                        if let error = error {
                            print("func uploadComment(): Error uploading comment: \(error.localizedDescription)")
                        } else {
                            // Update commentMap with the new comment at the top
                            DispatchQueue.main.async {
                                self?.commentMap.insert(CommentsData(
                                    id: id,
                                    userId: currentUserId,
                                    timestamp: timestamp,
                                    username: username,
                                    comment: self?.comment ?? ""
                                ), at: 0) // Insert at the top
                                
                                self?.comment = "" // Clear the comment input field
                                Task {
                                    await self?.savePosts()
                                }
                            }
                        }
                    }
                }
        }
    }
    
    func retrievePhotos() async {
        postMap = []
        commentMap = []

        // Get data from Firestore
        databaseRef.collection("timeline")
            .order(by: "timestamp", descending: true)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("func retrievePhotos():Error retrieving photos: \(error.localizedDescription)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let group = DispatchGroup()
                
                for doc in snapshot.documents {
                    group.enter()
                    
                    guard
                        let id = doc["id"] as? String,
                        let userId = doc["userId"] as? String,
                        let dayOfYear = doc["dayOfYear"] as? Int,
                        let path = doc["url"] as? String,
                        let timestamp = doc["timestamp"] as? Timestamp,
                        let username = doc["username"] as? String,
                        let caption = doc["caption"] as? String,
                        let likeCount = doc["likeCount"] as? Int,
                        let likes = doc["likes"] as? [String: Bool]
                    else {
                        group.leave()
                        continue
                    }
                    
                    // Fetch comments
                    self?.databaseRef.collection("timeline").document(doc.documentID).collection("Comments")
                        .order(by: "timestamp", descending: true)
                        .getDocuments { commentsSnapshot, commentsError in
                            if let commentsError = commentsError {
                                print("func retrivePhotos(): Error retrieving comments: \(commentsError.localizedDescription)")
                            } else {
                                if let commentsSnapshot = commentsSnapshot {
                                    self?.commentMap = commentsSnapshot.documents.compactMap { com in
                                        guard
                                            let commentId = com["id"] as? String,
                                            let commentUserId = com["userId"] as? String,
                                            let commentTimestamp = com["timestamp"] as? Timestamp,
                                            let commentUsername = com["username"] as? String,
                                            let commentText = com["comment"] as? String
                                        else { return nil }
                                        
                                        return CommentsData(
                                            id: commentId,
                                            userId: commentUserId,
                                            timestamp: commentTimestamp,
                                            username: commentUsername,
                                            comment: commentText
                                        )
                                    }
                                }
                            }
                            
                            // Retrieve image data
                            let fileRef = self?.storageRef.child(path)
                            fileRef?.getData(maxSize: 5 * 1024 * 1024) { result in
                                switch result {
                                case .success(let data):
                                    if let image = UIImage(data: data) {
                                        DispatchQueue.main.async {
                                            self?.postMap.append(PostData(
                                                id: id,
                                                userId: userId,
                                                dayOfYear: dayOfYear,
                                                image: image,
                                                timestamp: timestamp,
                                                username: username,
                                                caption: caption,
                                                likeCount: likeCount,
                                                likes: likes,
                                                commentsData: self?.commentMap ?? []
                                            ))
                                        }
                                    }
                                case .failure(let error):
                                    print("func retrivePhotos(): Error fetching image data: \(error.localizedDescription)")
                                }
                                
                                group.leave()
                            }
                        }
                }
                
                group.notify(queue: .main) {
                    self?.postMap.sort(by: { $0.timestamp.dateValue() > $1.timestamp.dateValue() })
                }
            }
        postMap = []
        commentMap = []
    }

    private func fetchUsername(for userId: String, completion: @escaping (String?) -> Void) async {
        let userRef = databaseRef.collection("users").document(userId)
        userRef.getDocument { document, error in
            if let error = error {
                print("func fetchUsername(): Error fetching user document: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard
                let document = document, document.exists,
                let data = document.data(),
                let authData = data["AuthenticationData"] as? [String: Any],
                let username = authData["username"] as? String
            else {
                print("func fetchUsername(): User document data is missing or invalid")
                completion(nil)
                return
            }
            
            completion(username)
        }
    }
    
    @Published var habitDataForDayTimeline: [String: Prod1.HabitData] = [:] // Dictionary = [Day of year: habit data]
    func listenForTimelineHabitData(id: String, userId: String, dayOfYear: Int) async {
        
        let userRef = self.databaseRef.collection("users").document(userId)
        
        // Reference to dayOfYear document in habitData sub-collection
        let habitDataRef = userRef.collection("HabitData").document(String(dayOfYear))
        
        // Add a snapshot listener to listen for changes in the dayOfYear document
        habitDataRef.addSnapshotListener { documentSnapshot, error in
            // Check if data exists
            guard let habitDocument = documentSnapshot else {
                print("func listenForTimelineHabitData(): Error fetching HabitData: \(error!)")
                return
            }
            // Check if document exists
            guard habitDocument.exists else {
                return
            }
            
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
        }
    }
    
    @Published var heart: Bool = false
    @Published var comments: Bool = false
    @Published var paperplane: Bool = false
    func likePost(postId: String) async {
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        // Create reference to the timeline collection
        let timelineRef = self.databaseRef.collection("timeline")
        
        // Query to find the document with the matching postId
        let query = timelineRef.whereField("id", isEqualTo: postId)
                
        query.getDocuments { querySnapshot, error in
            if let error = error {
                print("func likePost(): Error querying documents: \(error.localizedDescription)")
                return
            }
            
            // Print the number of documents found
            if let documents = querySnapshot?.documents, !documents.isEmpty {
                
                // Retrieve the document ID of the matching document
                let document = documents.first
                let documentId = document?.documentID
                guard let documentId = documentId else {
                    print("func likePost(): No document found with the given postId")
                    return
                }
                
                // Create a reference to that document
                let postRef = timelineRef.document(documentId)
                
                postRef.getDocument { document, error in
                    if let error = error {
                        print("func likePost(): Error retrieving document: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let document = document, document.exists else {
                        print("func likePost(): Document does not exist")
                        return
                    }
                    
                    var likes = document.data()?["likes"] as? [String: Bool] ?? [:]
                    let currentStatus = likes[currentUserId] ?? false
                    likes[currentUserId] = !currentStatus
                    
                    postRef.updateData([
                        "likes": likes
                    ]) { error in
                        if let error = error {
                            print("func likePost(): Error updating likes: \(error.localizedDescription)")
                            return
                        }
                        
                        var likeCount = document.data()?["likeCount"] as? Int ?? 0
                        likeCount = currentStatus ? likeCount - 1 : likeCount + 1
                        
                        postRef.updateData([
                            "likeCount": likeCount
                        ]) { error in
                            if let error = error {
                                print("func likePost(): Error updating likeCount: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                
                // Optionally, add a snapshot listener to keep track of real-time changes
                postRef.addSnapshotListener { documentSnapshot, error in
                    if let error = error {
                        print("func likePost(): Error listening for document changes: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let document = documentSnapshot, document.exists else {
                        print("func likePost(): Document snapshot does not exist")
                        return
                    }
                    
                    guard let data = document.data() else {
                        print("func likePost(): Document data is empty")
                        return
                    }
                    
                    if let likes = data["likes"] as? [String: Bool] {
                        DispatchQueue.main.async {
                            self.heart = likes[currentUserId] ?? false
                        }
                    }
                }
            } else {
                print("func likePost(): No documents found in the query snapshot")
            }
        }
    }
    
    @Published var postList: [String] = []
    func savePosts() async {
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        let timelineRef = self.databaseRef.collection("timeline")
        
        // Empty list of posts
        self.postList = []
        
        // Find the relevant posts
        let query = timelineRef.whereField("userId", isEqualTo: currentUserId)
        query.getDocuments { [weak self] querySnapshot, error in
            if let error = error {
                print("func savePosts(): error querying timeline collection: \(error.localizedDescription)")
                return
            }
            
            guard let documents = querySnapshot?.documents, !documents.isEmpty else {
                print("func savePosts(): There are no documents")
                return
            }
            
            // Append each relevant post's id field
            for doc in documents {
                if let postId = doc.data()["id"] as? String { // Retrieve the id field
                    self?.postList.append(postId)
                }
            }
            
            // Update database
            userRef.updateData([
                "Posts": self?.postList ?? []
            ]) { error in
                if let error = error {
                    print("func savePosts(): error updating posts: \(error.localizedDescription)")
                } else {

                }
            }
        }
    }
    
    func retrieveUserPosts() async {
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }

        postMap = []
        commentMap = []

        let userRef = self.databaseRef.collection("users").document(currentUserId)
        
        userRef.getDocument { [weak self] document, error in
            if let error = error {
                print("func retrieveUserPosts(): Error retrieving user document: \(error.localizedDescription)")
                return
            }

            guard let document = document, document.exists else {
                print("func retrieveUserPosts(): document does not exist")
                return
            }
                    
            guard let data = document.data(),
                  let postIds = data["Posts"] as? [String] else {
                print("func retrieveUserPosts(): No posts found for the user")
                return
            }

            let group = DispatchGroup()
            
            for postId in postIds {
                group.enter()
                self?.databaseRef.collection("timeline").whereField("id", isEqualTo: postId).getDocuments { querySnapshot, error in
                    if let error = error {
                        print("Error retrieving post document: \(error.localizedDescription)")
                        group.leave()
                        return
                    }

                    guard let documents = querySnapshot?.documents, !documents.isEmpty else {
                        print("func retrieveUserPosts(): No documents match the query for postId \(postId)")
                        group.leave()
                        return
                    }

                    // Assume there is only one document per postId
                    if let postDoc = documents.first {
                        if let postData = postDoc.data() as? [String: Any] {
                            let userId = postData["userId"] as? String
                            let dayOfYear = postData["dayOfYear"] as? Int
                            let path = postData["url"] as? String
                            let timestamp = postData["timestamp"] as? Timestamp
                            let username = postData["username"] as? String
                            let caption = postData["caption"] as? String
                            let likeCount = postData["likeCount"] as? Int
                            let likes = postData["likes"] as? [String: Bool]
                            
                            // Ensure all required fields are present
                            guard let userId = userId,
                                  let dayOfYear = dayOfYear,
                                  let path = path,
                                  let timestamp = timestamp,
                                  let username = username,
                                  let caption = caption,
                                  let likeCount = likeCount,
                                  let likes = likes else {
                                print("func retrieveUserPosts(): Some post fields are missing or invalid")
                                group.leave()
                                return
                            }

                            // Fetch comments
                            self?.databaseRef.collection("timeline").document(postDoc.documentID).collection("Comments")
                                .order(by: "timestamp", descending: true)
                                .getDocuments { commentsSnapshot, commentsError in
                                    var postComments: [CommentsData] = []
                                    if let commentsError = commentsError {
                                        print("Error retrieving comments: \(commentsError.localizedDescription)")
                                    } else {
                                        if let commentsSnapshot = commentsSnapshot {
                                            postComments = commentsSnapshot.documents.compactMap { com in
                                                guard
                                                    let commentId = com["id"] as? String,
                                                    let commentUserId = com["userId"] as? String,
                                                    let commentTimestamp = com["timestamp"] as? Timestamp,
                                                    let commentUsername = com["username"] as? String,
                                                    let commentText = com["comment"] as? String
                                                else { return nil }
                                                
                                                return CommentsData(
                                                    id: commentId,
                                                    userId: commentUserId,
                                                    timestamp: commentTimestamp,
                                                    username: commentUsername,
                                                    comment: commentText
                                                )
                                            }
                                        }
                                    }

                                    // Retrieve image data
                                    let fileRef = self?.storageRef.child(path)
                                    fileRef?.getData(maxSize: 5 * 1024 * 1024) { result in
                                        switch result {
                                        case .success(let data):
                                            if let image = UIImage(data: data) {
                                                DispatchQueue.main.async {
                                                    self?.postMap.append(PostData(
                                                        id: postId,  // Use postId from the document
                                                        userId: userId,
                                                        dayOfYear: dayOfYear,
                                                        image: image,
                                                        timestamp: timestamp,
                                                        username: username,
                                                        caption: caption,
                                                        likeCount: likeCount,
                                                        likes: likes,
                                                        commentsData: postComments
                                                    ))
                                                }
                                            }
                                        case .failure(let error):
                                            print("func retrieveUserPosts(): Error fetching image data: \(error.localizedDescription)")
                                        }

                                        group.leave()
                                    }
                                }
                        } else {
                            print("func retrieveUserPosts(): Post data is not valid")
                            group.leave()
                        }
                    } else {
                        print("func retrieveUserPosts(): No document found for postId \(postId)")
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                self?.postMap.sort(by: { $0.timestamp.dateValue() > $1.timestamp.dateValue() })
            }
        }
    }
    
    @Published var isProfileViewVisible: Bool = false
}

//
//  AuthenticationViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 12/03/2024.
//

// MARK: FIX THIS MESS!!!

import SwiftUI
import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI

//  MARK: User Input Validator
protocol AuthFormValidation {
    var isFormValid: Bool { get }
}

@MainActor
class AuthState: ObservableObject {
    
    // MARK: AuthState
    let authRef = Auth.auth()
    let databaseRef = Firestore.firestore()
    let storageRef = Storage.storage().reference()
    
    @Published var userSession: FirebaseAuth.User? = nil
    @Published var currentUser: AuthModel?
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
        
        // Initialising weekDayIndexCounter to the current day of the week
        self.weekDayIndexCounter = self.weekdayIndex(forDayOfYear: self.currentDayOfYear, inYear: self.currentYear) ?? 0
        
        // Initialising currentDayOfWeek
        self.currentDayOfWeek = self.currentDayOfYear
    }
    
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
                        let decodedAuthenticationData = try Firestore.Decoder().decode(Prod1.AuthModel.self, from: authenticationData)
                        self.currentUser = decodedAuthenticationData
                    } catch {
                        print("Error decoding AuthenticationData: \(error.localizedDescription)")
                    }
                }
                
                // Fetch and decode Analytics
                if let analytics = userData["Analytics"] as? [String: Any] {
                    do {
                        let decodedAnalytics = try Firestore.Decoder().decode(Prod1.AnalyticsModel.self, from: analytics)
                        self.dayTracker = decodedAnalytics.dayTracker
                    } catch {
                        print("Error decoding Analytics: \(error.localizedDescription)")
                    }
                }
                
                // Fetch and decode progress data
                if let progressData = userData["Progress"] as? [String: Any] {
                    do {
                        let decodedProgressData = try Firestore.Decoder().decode(Prod1.ProgressDataModel.self, from: progressData)
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
        let circleData = userRef.collection("CircleData").document("\(currentYear)-\(currentDayOfYear)")
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
                        let decodedHabitData = try Firestore.Decoder().decode(Prod1.HabitDataModel.self, from: habitData)
                        self.habitData = decodedHabitData
                    } catch {
                        print("Error decoding HabitData: \(error.localizedDescription)")
                    }
                }
                
                // Fetch and decode task data
                if let taskData = circleData["TaskData"] as? [String: Any] {
                    do {
                        let decodedTaskData = try Firestore.Decoder().decode(Prod1.TaskDataModel.self, from: taskData)
                        self.taskData = decodedTaskData
                        self.tasks = decodedTaskData.tasks
                        self.taskTimerDictionary = decodedTaskData.taskTimerDictionary
                    } catch {
                        print("Error decoding TaskData: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        let monthlyProgressDocRef = userRef.collection("MonthlyProgress").document("\(currentYear)-\(currentMonth)")
        monthlyProgressDocRef.addSnapshotListener { DocumentSnapshot, error in
            guard let monthlyProgressDoc = DocumentSnapshot else {
                print("func listenForUser(): error fetching monthlyProgressDoc")
                return
            }
            
            if !monthlyProgressDoc.exists {
                print("func listenForUser(): monthlyProgressDoc doesn't exist")
                return
            }
            
            if let monthlyProgressData = monthlyProgressDoc.data(),
               let TaskTimes = monthlyProgressData["TaskTimes"] as? [String: Int] {
                self.monthlyProgressTimerDictionary = TaskTimes
            } else {
                print("func listenForUser(): failed to define TaskTimes")
            }
        }
    }
    
    
    // MARK: AuthenticationViewModel
    @Published var secureField: Bool = false
    @Published var logInError: Bool = false
    
    @Published var signUpError: Bool = false
    @Published var usernameExists: Bool = false
    
    enum usernameExistsError: Error {
        case usernameAlreadyExists
    }
    
    
    // MARK: TaskDataViewModel
    @Published var taskData: TaskDataModel?
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
    let maxTime = 3600
    
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
    
    @Published var maxWidth: Double = 340
    @Published var newTimeArray: [String: Int] = [:]
    
    @Published var isTimerOn: Bool = false
    @Published var timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect() // Just initializing 'timer' variable
    @Published var progressTimerDictionary: [String: Int] = [:] // Dictionary = [Task Title : cumulative TimerCount for task]
    @Published var monthlyProgressTimerDictionary: [String: Int] = [:] // Dictionary = [Task Title : cumulative TimerCount for task]
    @Published var taskTimerDictionary: [String: Int] = [:] // Dictionary = [Task Title : Timer count for task]
    @Published var taskName = "Task"
    @Published var taskTime: Int = 0 {
        didSet {
            formattedTaskTime = formatTime(taskTime)
        }
    }
    
    @Published var timerCount: Int = 0
    @Published var formattedTaskTime: String = "00:00:00"
    
    @Published var formattedCumulativeTime: String = "00:00:00"
    @Published var cumulativeTime: Int = 0 {
        didSet {
            formattedCumulativeTime = formatTime(cumulativeTime)
        }
    }
    
    @Published var taskSum: Int = 0
    
    @Published var monthlyTime: String = ""
    
    @Published var dailyTime: String = ""
    
    @Published var placeholderTasks: [Int] = [1]
    
    @Published var selectedTask: String? = nil
    @Published var selectedCalendarTask: String? = nil
    
    
    // MARK: ProgressDataViewModel
    @Published var progressData: ProgressDataModel?
    
    @Published var selectedChartPosition: Int?
    @Published var taskSectorRange: [String: Range<Int>] = [:]
    
    @Published var isViewYourProgressVisible = false
    
    @Published var docTitles: [String] = []
    
    @Published var dictionaryCount: Int = 0
    @Published var habitDataForDay: [String: Prod1.HabitDataModel] = [:] // Dictionary = [Day of year: habit data]
    @Published var taskDataForDay: [String: Prod1.TaskDataModel] = [:] // Dictionary = [Day of year: task data]
    
    @Published var cumulativeProg: Int = 0
    @Published var cumulativeTasks: [String: Int] = [:]
    
    
    // MARK: HabitDataViewModel
    @Published var habitData: HabitDataModel?
    @Published var dayConstant: Int = 0
    @Published var weekDay: [String] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    @Published var isBlurViewVisible: Bool = false
    @Published var isProfileBlurViewVisible: Bool = false
    @Published var isPostBlurViewVisible: Bool = false
    @Published var isAddHabitVisible = false
    @Published var habitIdArray: [String] = []
    @Published var habitIdName: [String: String] = [:] // Dictionary = [Habit Id : Habit Name]
    @Published var habitPositions: [String: CGSize] = [:] // Dictionary = [Habit Id : Habit coordinates]
    @Published var isHabitStriked: [String: Bool] = [:] // Dictionary = [Habit Id : Striked/ Not Striked]
    @Published var selectedHabit: String? // String that's about to be removed. '?' shows that it could be 'nil'
    @Published var habitName: String = ""
    @Published var habitTime: String = ""
    @Published var offsetX: CGFloat = 0
    @Published var habitDataForDayTimeline: [String: Prod1.HabitDataModel] = [:] // Dictionary = [Day of year: habit data]
    
    
    // MARK: AnalyticsViewModel
    @Published var analytics: AnalyticsModel?
    @Published var dayTracker: [Int] = []
    @Published var dayTrackerOffset: Int = 0
    @Published var habitStreak: Int = 0
    func dayTrackerMath() async {
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
    
    func analyticsUpdate() async {
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
    
    func yesterdaysDayChecker(for yesterdaysDay: Int) -> String {
        if yesterdaysDay == 0 {
            let previousYear = currentYear - 1
            // Leap year check
            let isLeap = (previousYear % 4 == 0 && previousYear % 100 != 0) || (previousYear % 400 == 0)
            let lastDay = isLeap ? 366 : 365
            return "\(previousYear)-\(lastDay)"
        } else {
            return "\(currentYear)-\(yesterdaysDay)"
        }
    }
    
    func habitStreakTracker() async {
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        let circleDataRef = userRef.collection("CircleData").document(yesterdaysDayChecker(for: (self.currentDayOfYear - 1)))
        
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
    
    func tommorrowsDayChecker(for tommorrowsDay: Int) -> String {
        // Check if current year is a leap year
        let isLeap = (currentYear % 4 == 0 && currentYear % 100 != 0) || (currentYear % 400 == 0)
        let lastDay = isLeap ? 366 : 365

        if tommorrowsDay > lastDay {
            // Tomorrow is in the next year, so use next year and day 1
            return "\(currentYear + 1)-1"
        } else {
            // Tomorrow is still in the current year
            return "\(currentYear)-\(tommorrowsDay)"
        }
    }
    
    
    //  MARK: FriendsViewModel
    @Published var addFriendsError = false
    @Published var friendAlreadyExistsError = false
    @Published var friendAdded: Bool = false
    @Published var friendMessage = ""
    @Published var isFriendsVisible: Bool = false
    @Published var isAddFriendsVisible: Bool = false
    
    @Published var searchResults: [String: Int] = [:]
    
    @Published var friendsHabitData: [String: HabitDataModel] = [:]
    @Published var friendsTaskData: [String: TaskDataModel] = [:]
    
    @Published var friendCount: Int = 0
    @Published var friendOrFriends: String = "Friends"
    
    // MARK: SettingsViewModel
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
    @Published var comingSoonAlert: Bool = false
    @Published var isSettingsVisible = false
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
    
    
    //  MARK: Clear Data
    func clearData() {
        currentUser = nil
        taskData = nil
        habitData = nil
        progressTasks = []
        taskDecimalDict = [:]
        taskPercentageDict = [:]
        progressTimerDictionary = [:]
        monthlyProgressTimerDictionary = [:]
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
    
    
    // MARK: FeedViewModel
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
    
    
    // MARK: CUSTOM COLOURS
    @Published var darkGray: Color = Color(.sRGB, red: 0.1, green: 0.1, blue: 0.1, opacity: 1.0)
}

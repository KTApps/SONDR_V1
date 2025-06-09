//
//  AuthenticationViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 12/03/2024.
//

// MARK: FIX THIS MESS!!!

import SwiftUI
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
    @Published var profileImageCache: [String: Image] = [:]
    @Published var comingSoonAlert: Bool = false
    @Published var isSettingsVisible = false
    
    
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

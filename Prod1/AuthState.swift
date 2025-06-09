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
            let circleDataRef = userRef.collection("CircleData").document("\(currentYear)-\(currentDayOfYear)")
            
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
        
        let circleDataRef = self.databaseRef.collection("users").document(userId).collection("CircleData").document("\(currentYear)-\(self.currentDayOfYear)")
        
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
     
    func taskTimeCaller(for task: String) async {
        guard let userId = self.authRef.currentUser?.uid else {
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(userId)
        let circleDataRef = userRef.collection("CircleData").document("\(currentYear)-\(currentDayOfYear)")
        let monthlyProgressRef = userRef.collection("MonthlyProgress").document("\(currentYear)-\(currentMonth)")
        
        do {
            let circleDataDoc = try await circleDataRef.getDocument()
            if let circleData = circleDataDoc.data(),
               let taskData = circleData["TaskData"] as? [String: Any] {
                let taskTimerDict = taskData["taskTimerDictionary"] as? [String: Int]
                self.taskTime = taskTimerDict?[task] ?? 0
            } else {
                print("func taskTimeCaller(): circleData's or taskData's data is missing")
            }
            
            let monthlyProgressDoc = try await monthlyProgressRef.getDocument()
            if let monthlyProgressData = monthlyProgressDoc.data() {
                let taskTimes = monthlyProgressData["TaskTimes"] as? [String: Int]
                self.cumulativeTime = taskTimes?[task] ?? 0
            } else {
                print("func taskTimeCaller(): monthlyProgress data is missing")
            }
        } catch {
            print("\(error)")
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
                    let newMaxTime = ((currentTime / 100) + 36) * 100
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
    
    func formatTime(_ time: Int) -> String {
        let hours = time / 3600
        let minutes = (time % 3600) / 60
        let seconds = time % 60
        
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    @Published var formattedCumulativeTime: String = "00:00:00"
    @Published var cumulativeTime: Int = 0 {
        didSet {
            formattedCumulativeTime = formatTime(cumulativeTime)
        }
    }
    
    func updateTaskTimerInFirestore(taskName: String, monthlyProgressCount: Int, timerCount: Int) {
        guard let userId = userSession?.uid else {
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(userId)
        userRef.updateData([
            "Progress.progressTimerDictionary.\(taskName)": FieldValue.increment(Int64(timerCount))
        ])
        
        let monthlyProgressRef = userRef.collection("MonthlyProgress").document("\(currentYear)-\(currentMonth)")
        monthlyProgressRef.updateData([
            "TaskTimes.\(taskName)" : monthlyProgressCount
        ])
        
        let circleDataRef = userRef.collection("CircleData").document("\(currentYear)-\(currentDayOfYear)")
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
    
    @Published var taskSum: Int = 0
    func taskTimerDictionarySum(dayOfYear: Int) {
        guard let currentUserId = userSession?.uid else {
            return
        }
        
        self.taskSum = 0
        
        let CircleDataRef = self.databaseRef.collection("users").document(currentUserId).collection("CircleData").document("\(currentYear)-\(dayOfYear)")
        
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
    
    @Published var monthlyTime: String = ""
    
    func monthlyTime(for task: String) -> String {
        if taskName == "Task" {
            return timeFormat(cumulativeProg)
        } else {
            return timeFormat((task != "" ? monthlyProgressTimerDictionary[task] : cumulativeTime) ?? 0)
        }
    }
    
    @Published var dailyTime: String = ""
    
    func dailyTime(for task: String) -> String {
        if taskName == "Task" {
            return timeFormat(taskTimerDictionary.values.reduce(0, +))
        } else {
            return timeFormat((task != "" ? taskTimerDictionary[task] : taskTime) ?? 0)
        }
    }
    
    func calendarCircleDailyTime(for task: String) -> String {
        return timeFormat((task != "" ? taskTimerDictionary[task] : taskSum) ?? 0)
    }
    
    @Published var placeholderTasks: [Int] = [1]
    
    @Published var selectedTask: String? = nil
    @Published var selectedCalendarTask: String? = nil
    func taskForTime(for time: Double, tasks: [String], timeSpent: [String: Int]) -> String? {
        var cumulativeTime: Double = 0
        let timeSpentDouble = timeSpent.mapValues { Double($0) }
        let totalTime = timeSpentDouble.values.reduce(0, +)
                
        for task in tasks {
            if let taskTime = timeSpentDouble[task] {
                
                // Check if the clicked time falls within this task's range
                if time >= cumulativeTime && time < cumulativeTime + taskTime {
                    return task
                }
                
                // Update the cumulative time for the next task
                cumulativeTime += taskTime
            }
        }
        return nil
    }
    
    func timeFormat(_ seconds: Int) -> String {
        if seconds >= 3600 {
            let hours = seconds / 3600
            var result = "\(hours) \(hours == 1 ? "hr" : "hrs")"
            let remainder = seconds % 3600
            let minute = remainder / 60
            if minute >= 1 {
                result += " \(minute) \(minute == 1 ? "min" : "mins")"
            }
            return result
        } else if seconds >= 60 {
            let minutes = seconds / 60
            var result = "\(minutes) \(minutes == 1 ? "min" : "mins")"
            let remainder = seconds % 60
            if remainder > 0 {
                result += " \(remainder) \(remainder == 1 ? "sec" : "secs")"
            }
            return result
        } else {
            return "\(seconds) \(seconds == 1 ? "second" : "seconds")"
        }
    }
    
    
    // MARK: ProgressDataViewModel
    @Published var progressData: ProgressDataModel?
    func monthlyProgressSubCollection() async {
        guard let userId = self.authRef.currentUser?.uid else {
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(userId)
        let monthylProgressDocRef = userRef.collection("MonthlyProgress").document("\(currentYear)-\(currentMonth)")
        
        do {
            let monthylProgressDoc = try await monthylProgressDocRef.getDocument()
            guard !monthylProgressDoc.exists else {
                return
            }
            try await monthylProgressDocRef.setData([
                "TaskTimes" : [:]
            ])
        } catch {
            print("func monthlyProgressSubCollection(): error")
        }
    }
    
    @Published var selectedChartPosition: Int?
    @Published var taskSectorRange: [String: Range<Int>] = [:]
    
    func colorReturn(value: String) -> Color {
        if habitData?.isHabitStriked[value] == true {
            return .blue
        } else {
            return .gray
        }
    }
    
    @Published var isViewYourProgressVisible = false
    
    @Published var docTitles: [String] = []
    func fetchCircleDocRef() async {
        // Ensure the user is logged in
        guard let currentUserId = self.authRef.currentUser?.uid else {
            print("func fetchCircleDocRef(): User not logged in.")
            return
        }
        
        docTitles = []
        
        do {
            let circleDataRef = self.databaseRef.collection("users").document(currentUserId).collection("CircleData")
            
            for dayOffset in 1..<11 {
                let document = circleDataRef.document(yesterdaysDayChecker(for: (currentDayOfYear - dayOffset)))
                let docSnapshot = try await document.getDocument()
                
                if docSnapshot.exists {
                    let docId = document.documentID
                    let parts = docId.split(separator: "-")
                    if parts.count == 2, let year = Int(parts[0]), let day = Int(parts[1]) {
                        docTitles.append("\(year)\(day)")
                    }
                }
            }
        } catch {
            print("func fetchCircleDocRef(): Error fetching HabitData document: \(error.localizedDescription)")
        }
    }
    
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
    @Published var habitDataForDay: [String: Prod1.HabitDataModel] = [:] // Dictionary = [Day of year: habit data]
    @Published var taskDataForDay: [String: Prod1.TaskDataModel] = [:] // Dictionary = [Day of year: task data]
    func listenForCircleData(document: String) async {
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        // Reference to users document in Firestore
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        // Reference to dayOfYear document in habitData sub-collection
        let year = document.prefix(4)
        let day = document.dropFirst(4)
        let circleDataRef = userRef.collection("CircleData").document("\(year)-\(day)")
        
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
                        let decodedHabitData = try Firestore.Decoder().decode(Prod1.HabitDataModel.self, from: habitData)
                        // Update habitDataForDay dictionary with the fetched habit data
                        self.habitDataForDay[document] = decodedHabitData
                    } catch {
                        print("Error decoding HabitData for day \(document): \(error.localizedDescription)")
                    }
                }
                
                // Fetch and decode task data
                if let taskData = circleData["TaskData"] as? [String: Any] {
                    do {
                        let decodedTaskData = try Firestore.Decoder().decode(Prod1.TaskDataModel.self, from: taskData)
                        self.taskDataForDay[document] = decodedTaskData
                    } catch {
                        print("Error decoding TaskData: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
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
                let docId = document.documentID
                let parts = docId.split(separator: "-")
                if parts.count == 2 {
                    // The document ID is the day of the year, so convert it to an Int
                    if let dayOfYear = Int(parts[1]), dayOfYear >= startDayOfYear, dayOfYear <= endDayOfYear {
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
                } else {
                    print("func cumulativeProgress(): you'll need to migrate the database. The 'CircleData' document IDs are wrong")
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
            
            guard let document = document, document.exists, let userData = document.data() else {
                print("func updateCumulativeTasks(): Analytics document does not exist or data is nil")
                return
            }
            
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
    
    private func yesterdaysDayChecker(for yesterdaysDay: Int) -> String {
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
    
    @Published var friendsHabitData: [String: HabitDataModel] = [:]
    @Published var friendsTaskData: [String: TaskDataModel] = [:]
    
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

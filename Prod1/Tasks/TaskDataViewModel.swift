//
//  TaskDataViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 08/06/2025.
//

import Foundation
import FirebaseFirestore

protocol TaskDataViewModel {
    func taskAdder() async
    func newTaskAdder(task: String) async
    func taskTimeCaller(for task: String) async
    func progressPercentage()
    func updateTaskProgress(userId: String)
    func updateTaskDecimalDict()
    func newTimeCalc()
    func formatTime(_ time: Int) -> String
    func updateTaskTimerInFirestore(taskName: String, monthlyProgressCount: Int, timerCount: Int)
    func resetTimer() -> Int?
    func taskTimerDictionarySum(dayOfYear: Int)
    func monthlyTime(for task: String) -> String
    func dailyTime(for task: String) -> String
    func calendarCircleDailyTime(for task: String) -> String
    func taskForTime(for time: Double, tasks: [String], timeSpent: [String: Int]) -> String?
    func timeFormat(_ seconds: Int) -> String
}

extension AuthState: TaskDataViewModel {
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
    
    func updateTaskProgress(userId: String) {
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
    
    func newTimeCalc() {
        for item in progressTasks {
            let newTime = (maxWidth * (taskDecimalDict[item] ?? 0))
            newTimeArray[item] = Int(newTime)
        }
    }
    
    func formatTime(_ time: Int) -> String {
        let hours = time / 3600
        let minutes = (time % 3600) / 60
        let seconds = time % 60
        
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
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
    
    func monthlyTime(for task: String) -> String {
        if taskName == "Task" {
            return timeFormat(cumulativeProg)
        } else {
            return timeFormat((task != "" ? monthlyProgressTimerDictionary[task] : cumulativeTime) ?? 0)
        }
    }
    
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
            return result
        } else {
            return "0 mins"
        }
    }
}

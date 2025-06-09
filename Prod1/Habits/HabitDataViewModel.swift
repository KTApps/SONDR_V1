//
//  HabitDataViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 08/06/2025.
//

import SwiftUI
import FirebaseFirestore

protocol HabitDataViewModel {
    func circleSubCollection() async
    func newCircleDoc() async
    func weekdayMinus()
    func weekdayPlus()
    func weekdayIndex(forDayOfYear dayOfYear: Int, inYear year: Int) -> Int?
    func habitAppender()
    func habitStriker(value: String)
    func habitRemover(value: String)
    func listenForTimelineHabitData(id: String, userId: String, dayOfYear: Int) async
    func colorReturn(value: String) -> Color
}

extension AuthState: HabitDataViewModel {
    func circleSubCollection() async {
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        
        // Iterate over the next six days
        for i in 0..<7 {
            // Calculate the day of year for the current day plus 'i'
            let nextDayOfYear = currentDayOfYear + i
            
            // Construct the document reference for the current day
            let currentDayDocumentRef = userRef.collection("CircleData").document(tommorrowsDayChecker(for: nextDayOfYear))
            
            do {
                // Check if the document for the current day already exists
                let documentSnapshot = try await currentDayDocumentRef.getDocument()
                
                // If the document for the current day doesn't exist, create it
                if !documentSnapshot.exists {
                    // Store habit data as a subcollection within the current day document
                    let habitData = Prod1.HabitDataModel(habitIdArray: habitIdArray,
                                                    habitIdName: habitIdName,
                                                    isHabitStriked: isHabitStriked)
                    
                    let encodedHabitData = try Firestore.Encoder().encode(habitData)
                    try await currentDayDocumentRef.setData(["HabitData": encodedHabitData])
                    
                    // Store task data
                    let taskData = Prod1.TaskDataModel(tasks: tasks,
                                                  taskTimerDictionary: taskTimerDictionary)
                    let encodedTaskData = try Firestore.Encoder().encode(taskData)
                    try await currentDayDocumentRef.updateData(["TaskData": encodedTaskData])
                    
                }
            } catch {
                print("Error checking or updating HabitData for day \(nextDayOfYear): \(error)")
            }
        }
    }
    
    func newCircleDoc() async {
        guard let currentUserId = self.authRef.currentUser?.uid else {
            return
        }
        
        let userRef = self.databaseRef.collection("users").document(currentUserId)
        
        // Reference the current day document
        let currentDayDocumentRef = userRef.collection("CircleData").document("\(currentYear)-\(currentDayOfYear)")
        
        do {
            // Fetch the current day document's data
            let currentDayDocumentSnapshot = try await currentDayDocumentRef.getDocument()
            
            var currentDayData: [String: Any]
                    
            // Check if today's document exists
            if let fetchedData = currentDayDocumentSnapshot.data() {
                currentDayData = fetchedData
            } else {
                print("Current day's document does not exist. Creating a new one.")
                
                // Create default HabitData and TaskData structures
                let defaultHabitData: [String: Any] = [
                    "habitIdArray": [],
                    "habitIdName": [:],
                    "isHabitStriked": [:]  // Default empty habit tracker
                ]
                
                let defaultTaskData: [String: Any] = [
                    "tasks": [],
                    "taskTimerDictionary": [:]
                ]

                // Create the document with default data
                currentDayData = [
                    "HabitData": defaultHabitData,
                    "TaskData": defaultTaskData
                ]

                // Save it to Firestore
                try await currentDayDocumentRef.setData(currentDayData)
                print("New document for current day created successfully.")
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
            for i in (currentDayOfYear + 1)...nextDayInDocs {
                
                // Construct the document reference for the next day
                let nextDayDocumentRef = userRef.collection("CircleData").document(tommorrowsDayChecker(for: i))
                
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
    
    func weekdayMinus() {
        if currentDayOfWeek == currentDayOfYear {
            currentDayOfWeek += 6
        } else {
            currentDayOfWeek -= 1
        }
        Task {
            let documentTitle = "\(currentYear)\(currentDayOfWeek)"
            await listenForCircleData(document: documentTitle)
        }
    }
    
    func weekdayPlus() {
        if currentDayOfWeek == currentDayOfYear + 6 {
            currentDayOfWeek -= 6
        } else {
            currentDayOfWeek += 1
        }
        Task {
            let documentTitle = "\(currentYear)\(currentDayOfWeek)"
            await listenForCircleData(document: documentTitle)
        }
    }
    
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
                let habitDataRef = userRef.collection("CircleData").document(tommorrowsDayChecker(for: nextDayOfYear))
                
                habitDataRef.updateData([
                    "HabitData.habitIdArray": FieldValue.arrayUnion([habitId]),
                    "HabitData.habitIdName.\(habitId)": habitName,
                    "HabitData.isHabitStriked.\(habitId)": false
                ])
                
            }
        } else {
            let documentTitle = "\(currentYear)\(currentDayOfWeek)"
            habitDataForDay[documentTitle]?.isHabitStriked[habitId] = false
            
            let habitDataRef = userRef.collection("CircleData").document("\(currentYear)-\(currentDayOfWeek)")
            
            habitDataRef.updateData([
                "HabitData.habitIdArray": FieldValue.arrayUnion([habitId]),
                "HabitData.habitIdName.\(habitId)": habitName,
                "HabitData.isHabitStriked.\(habitId)": false
            ])
            
            for i in 1..<7 {
                let nextDayOfYear = currentDayOfYear + i
                let habitDataRef = userRef.collection("CircleData").document(tommorrowsDayChecker(for: nextDayOfYear))
                
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
            let documentTitle = "\(currentYear)\(currentDayOfYear)"
            await listenForCircleData(document: documentTitle)
        }
    }
    
    func habitStriker(value: String) {
        guard let userId = userSession?.uid else {
            print("func habitStriker(): User is not logged in.")
            return
        }
        let documentTitle = "\(currentYear)\(currentDayOfWeek)"
        habitDataForDay[documentTitle]?.isHabitStriked[value]?.toggle()
        
        let userRef = self.databaseRef.collection("users").document(userId)
        let habitDataRef = userRef.collection("CircleData").document("\(currentYear)-\(currentDayOfWeek)")
        
        habitDataRef.updateData([
            "HabitData.isHabitStriked": habitDataForDay[documentTitle]?.isHabitStriked
        ])
        
        Task {
            await listenForUser()
            let documentTitle = "\(currentYear)\(currentDayOfWeek)"
            await listenForCircleData(document: documentTitle)
        }
        
        self.habitData = habitDataForDay[documentTitle] // Trigger a re-render by reassigning the object
    }
    
    func habitRemover(value: String) {
        guard let userId = userSession?.uid else {
            return
        }
        let documentTitle = "\(currentYear)\(currentDayOfWeek)"
        if var currentHabitData = self.habitDataForDay[documentTitle] {
            
            currentHabitData.habitIdArray.removeAll { $0 == value }
            currentHabitData.habitIdName.removeValue(forKey: value)
            currentHabitData.isHabitStriked.removeValue(forKey: value)
            
            self.habitDataForDay[documentTitle] = currentHabitData
        }
        
        let circleDocRef = self.databaseRef.collection("users").document(userId).collection("CircleData").document("\(currentYear)-\(currentDayOfWeek)")
        
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
                    let decodedHabitData = try Firestore.Decoder().decode(Prod1.HabitDataModel.self, from: habitData)
                    
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
    
    func colorReturn(value: String) -> Color {
        if habitData?.isHabitStriked[value] == true {
            return .blue
        } else {
            return .gray
        }
    }
}

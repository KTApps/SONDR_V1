//
//  ProgressDataViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 08/06/2025.
//

import FirebaseFirestore

protocol ProgressDataViewModel {
    func monthlyProgressSubCollection() async
    func fetchCircleDocRef() async
    func dayOfYear(year: Int, month: Int, day: Int) -> Int
    func isLeapYear(_ year: Int) -> Bool
    func dateFromDayOfYear(index: Int, year: Int, dayOfYear: Int) -> (month: Int, day: Int)?
    func listenForCircleData(document: String) async
    func cumulativeProgress()
    func updateCumulativeTasks()
}

extension AuthState: ProgressDataViewModel {
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
}

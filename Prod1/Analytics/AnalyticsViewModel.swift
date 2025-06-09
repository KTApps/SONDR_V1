//
//  AnalyticsViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 08/06/2025.
//

protocol AnalyticsViewModel {
    func dayTrackerMath() async
    func analyticsUpdate() async
    func yesterdaysDayChecker(for yesterdaysDay: Int) -> String
    func habitStreakTracker() async
    func tommorrowsDayChecker(for tommorrowsDay: Int) -> String
}

extension AuthState: AnalyticsViewModel {
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
}

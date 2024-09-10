import SwiftUI
import Firebase

class MockViewModel: ViewModel { // Ensure ViewModel is correctly inherited
    override init() {
        super.init()
        loadMockData()
    }
    
    func loadMockData() {
        let sampleUserId = "1234"
        let sampleUsername = "TestUser"
        
        // Mock data for habits
        let sampleHabitData: [Int: HabitData] = [
            1: HabitData(
                habitIdArray: ["habit1", "habit2"],
                habitIdName: [
                    "habit1": "Exercise",
                    "habit2": "Read"
                ],
                isHabitStriked: [
                    "habit1": true,
                    "habit2": false
                ]
            ),
            2: HabitData(
                habitIdArray: ["habit3", "habit4"],
                habitIdName: [
                    "habit3": "Meditate",
                    "habit4": "Write"
                ],
                isHabitStriked: [
                    "habit3": false,
                    "habit4": true
                ]
            )
        ]
        
        // Assign mock habit data
        self.habitDataForDay = sampleHabitData
        self.currentDayOfWeek = 1
        
        // Mock data for other properties
        self.currentUser = UserObject(id: sampleUserId, username: sampleUsername, email: "name@example.com")
        self.docTitles = Array(1...10) // Example list of document titles
    }
}

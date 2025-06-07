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
        // Use String keys like "2024-199" to match your real data
        let sampleHabitData: [String: HabitDataModel] = [
            "2024-199": HabitDataModel(
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
            "2024-198": HabitDataModel(
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
        self.currentDayOfWeek = 199 // Use the day part of your string key, or set as needed
        
        // Mock data for other properties
        self.currentUser = AuthModel(id: sampleUserId, username: sampleUsername, email: "name@example.com")
        // docTitles should be [String], matching your real document title format
        self.docTitles = ["2024-199", "2024-198"] // Example list of document titles
    }
}

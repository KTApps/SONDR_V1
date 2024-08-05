import SwiftUI
import Firebase

class MockViewModel: ViewModel {
    override init() {
        super.init()
        loadMockData()
    }
    
    func loadMockData() {
        // Mock data for posts and comments
        let sampleImage = UIImage(systemName: "photo") ?? UIImage()
        let sampleTimestamp = Timestamp(date: Date())
        let sampleUsername = "TestUser"
        let sampleCaption = "Hello World"
        let sampleId = "1234"
        let sampleUserId = "1234"
        let sampleDayOfYear = 100
        let sampleLikeCount = 100
        
        let sampleCommentId = "comment1234"
        let sampleCommentUserId = "commentUser1234"
        let sampleCommentUsername = "CommentUser"
        let sampleCommentText = "This is a comment"
        let sampleCommentTimestamp = Timestamp(date: Date())
        
        let sampleComments = [
            CommentsData(id: sampleCommentId, userId: sampleCommentUserId, timestamp: sampleCommentTimestamp, username: sampleCommentUsername, comment: sampleCommentText),
            CommentsData(id: "comment5678", userId: "commentUser5678", timestamp: sampleCommentTimestamp, username: "AnotherCommentUser", comment: "Another comment")
        ]
        
        self.postMap = [
            PostData(id: sampleId, userId: sampleUserId, dayOfYear: sampleDayOfYear, image: sampleImage, timestamp: sampleTimestamp, username: sampleUsername, caption: sampleCaption, likeCount: sampleLikeCount, likes: ["user1": true], commentsData: sampleComments),
            PostData(id: "5678", userId: sampleUserId, dayOfYear: sampleDayOfYear, image: sampleImage, timestamp: sampleTimestamp, username: "AnotherUser", caption: sampleCaption, likeCount: sampleLikeCount, likes: ["user2": true], commentsData: sampleComments),
            PostData(id: "91011", userId: sampleUserId, dayOfYear: sampleDayOfYear, image: sampleImage, timestamp: sampleTimestamp, username: "ExampleUser", caption: sampleCaption, likeCount: sampleLikeCount, likes: ["user3": true], commentsData: sampleComments)
        ]
        
        self.commentMap = sampleComments
        
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
            ),
        ]
        
        self.habitDataForDay = sampleHabitData
        self.currentDayOfWeek = 1
        
        // Mock data for other properties
        self.currentUser = UserObject(id: "1", username: "NameExample", email: "name@example.com")
        self.docTitles = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        self.caption = "Sample caption for preview"
    }
}

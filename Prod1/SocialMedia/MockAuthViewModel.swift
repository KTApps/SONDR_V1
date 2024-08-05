//
//  MockAuthViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 04/08/2024.
//

import SwiftUI
import Firebase

class MockViewModel: ViewModel {
    override init() {
        super.init()
        loadMockData()
    }
    
    func loadMockData() {
        // Replace with actual sample images and data
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
    }
}

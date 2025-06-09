//
//  AuthViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 08/06/2025.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

protocol AuthStateExtension {
    var userSession: FirebaseAuth.User? { get }
    var currentUser: AuthModel? { get }
    
    func signUp(withEmail email: String, password: String, username: String) async throws
    func logIn(withEmail email: String, password: String) async throws
    func listenForUser() async
}

extension AuthState: AuthStateExtension {
    func signUp(withEmail email: String, password: String, username: String) async throws {
        do {
            // Check if the username already exists
            let querySnapshot = try await self.databaseRef.collection("users")
                .whereField("AuthenticationData.username", isEqualTo: username)
                .getDocuments()

            if !querySnapshot.isEmpty {
                throw usernameExistsError.usernameAlreadyExists // Custom error
            }
            
            let result = try await self.authRef.createUser(withEmail: email, password: password) // Authenticates user
            self.userSession = result.user // user session = authenticated user
            
            taskName = "Task"
            taskTime = 0
            taskString = ""
            
            dayTracker = []
            
            progressTasks = []
            progressTimerDictionary = [:]
            taskDecimalDict = [:]
            taskMaxTime = [:]
            
            habitIdArray = []
            habitIdName = [:]
            isHabitStriked = [:]
            
            taskTimerDictionary = [:]
            tasks = []
            
            habitStreak = 0
            cumulativeTasks = [:]
            
            self.profileImage = nil
            
            // Store user data
            let user = AuthModel(id: result.user.uid,
                                  username: username,
                                  email: email) // initializes the raw data for encoding
            let encodedUser = try Firestore.Encoder().encode(user) // encodes raw data to encrypted data
            let userRef = self.databaseRef.collection("users").document(user.id)
            try await userRef.setData(["AuthenticationData": encodedUser])
            
            let analytics = Prod1.AnalyticsModel(dayTracker: dayTracker,
                                            dayTrackerOffset: dayTrackerOffset,
                                            habitStreak: habitStreak,
                                            cumulativeTasks: cumulativeTasks)
            let encodedAnalytics = try Firestore.Encoder().encode(analytics)
            try await userRef.updateData(["Analytics": encodedAnalytics])
            
            let progress = Prod1.ProgressDataModel(progressTasks: progressTasks,
                                              progressTimerDictionary: progressTimerDictionary,
                                              taskDecimalDict: taskDecimalDict,
                                              taskMaxTime: taskMaxTime)
            let encodedProgress = try Firestore.Encoder().encode(progress)
            try await userRef.updateData(["Progress": encodedProgress])
            
            // Create Circle Sub-Collection
            await circleSubCollection()
            await monthlyProgressSubCollection()
            
            Task {
                clearData()
                
                await listenForUser()
                let documentTitle = "\(currentYear)\(currentDayOfWeek)"
                await listenForCircleData(document: documentTitle)
                
                await fetchCircleDocRef()
                
                self.dayConstant = currentDayOfYear
                dayTracker.append(currentDayOfYear)
                await analyticsUpdate()
            }
        } catch usernameExistsError.usernameAlreadyExists {
            usernameExists.toggle()
            print("SIGN UP Failed... Username already exists.")
        } catch {
            signUpError.toggle()
            print("SIGN UP Failed... \(error.localizedDescription)")
        }
    }
    
    func logIn(withEmail email: String, password: String) async throws {
        do {
            taskName = "Task"
            taskTime = 0
            taskString = ""
            
            let result = try await self.authRef.signIn(withEmail: email, password: password) // signs into the authenticated user from firebase
            self.userSession = result.user // user session = authenticated user
            
            Task {
                await monthlyProgressSubCollection()
                await listenForUser()
                let documentTitle = "\(currentYear)\(currentDayOfWeek)"
                await listenForCircleData(document: documentTitle)
                
                await self.dayTrackerMath()
                if dayConstant < currentDayOfYear {
                    await newCircleDoc()
                }
                
                await self.fetchCircleDocRef()
                self.cumulativeProgress()
                await fetchAllFriendsData()
            }
            self.isFriendsVisible = false
        } catch {
            self.logInError.toggle()
            print("LOG IN Failed... \(error.localizedDescription)")
        }
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
}

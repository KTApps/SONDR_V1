//
//  AuthViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 08/06/2025.
//

import FirebaseAuth
import FirebaseFirestore

protocol AuthStateExtension {
    var userSession: FirebaseAuth.User? { get }
    var currentUser: AuthModel? { get }
    
    func signUp(withEmail email: String, username: String, password: String) async throws
    func logIn(withEmail email: String, password: String) async throws
}

extension AuthState: AuthStateExtension {
    func signUp(withEmail email: String, username: String, password: String) async throws {
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
}

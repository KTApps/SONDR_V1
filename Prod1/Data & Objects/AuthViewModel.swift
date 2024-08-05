//
//  AuthViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 14/03/2024.
//

import Foundation
import Firebase
import FirebaseFirestoreSwift

@MainActor
class AuthViewModel: ObservableObject {
    @Published var userSession: FirebaseAuth.User?
    @Published var currentUser: User?
    
    init() {
        self.userSession = Auth.auth().currentUser
        
        Task {
            await fetchUser()
        }
    }
    
    func fetchUser() async {
        guard let currentUserId = Auth.auth().currentUser?.uid // stores current users ID from firebase authentication
        else {
            return
        }
        
        guard let snapshot = try? await Firestore.firestore().collection("user").document(currentUserId).getDocument() // creates snapshot of users data from firestore database
        else {
            return
        }
        
        self.currentUser = try? snapshot.data(as: User.self) // current user = data from snapshot in the structure of the SettingsViewModel
        print("current user is \(self.currentUser)")
    }
    
    func LogIn(withEmail email: String, password: String) async throws {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password) // sign user in
            self.userSession = result.user // userSession = signed in user
            await fetchUser() // user fetch this users data
        } catch {
            print("LOG IN FAILED... \(error.localizedDescription)")
        }
    }
    
    func SignUp(withEmail email: String, password: String, fullname: String) async throws {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password) // Authenticate user
            self.userSession = result.user // userSession = Authenticated user
            let user = User(id: result.user.uid, fullname: fullname, email: email) // user = raw data to be encoded [SettingsViewModel(parameters)]
            let encodedUser = try Firestore.Encoder().encode(user) // encoding the raw data
            try await Firestore.firestore().collection("user").document(user.id).setData(encodedUser) // adding encoded data to the Firestore database
            await fetchUser() // fetching this users data from Firestore database
        } catch {
            print("SIGN UP FAILED... \(error.localizedDescription)")
        }
    }
    
    func SignOut() {
        do {
            try Auth.auth().signOut() // backend sign out
            self.userSession = nil // takes us back to login screen
            self.currentUser = nil // stops old data from appearing when logged into new user
        } catch {
            print("SIGNED OUT Failed... \(error.localizedDescription)")
        }
    }
    
    func DeleteAccount() {
        print("DELETE ACCOUNT")
    }
}

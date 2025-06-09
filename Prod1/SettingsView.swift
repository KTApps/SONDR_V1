//
//  SettingsView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 12/03/2024.
//

import SwiftUI
import PhotosUI

struct SettingsView: View {
    @ObservedObject var authState: AuthState
    
    var body: some View {
        if let user = authState.currentUser {
            List {
                Section {
                    HStack {
                        PhotosPicker(selection: $authState.selectedItem) {
                            if let profileImage = authState.profileImage {
                                profileImage
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 70, height: 70)
                                    .clipShape(Circle())
                            } else {
                                Text(user.initial)
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                                    .frame(width: 70, height: 70)
                                    .background(Color.gray)
                                    .clipShape(Circle())
                            }
                        }
                        VStack(alignment: .leading) {
                            Text(user.username)
                            Text(user.email)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section("Account") {
                    
                    Button(role: .destructive) {
                        withAnimation {
                            authState.isSettingsVisible = false
                            authState.isProfileBlurViewVisible = false
                            authState.signOut()
                        }
                    } label: {
                        SettingsButton(image: "arrow.left.circle.fill", action: "Log off")
                    }
                    
                    Button(role: .destructive) {
                        withAnimation {
                            authState.isSettingsVisible = false
                            authState.isProfileBlurViewVisible = false
                        }
                        Task {
                            try await authState.deleteAccount()
                        }
                    } label: {
                        SettingsButton(image: "x.circle.fill", action: "Delete Account")
                    }
                }
                .foregroundColor(.black)
            }
        } 
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        return SettingsView(authState: AuthState())
    }
}



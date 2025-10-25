//
//  Profile.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 05/07/2024.
//

import SwiftUI
import PhotosUI

struct ProfileOptions: View {
    @ObservedObject var authState: AuthState
    var body: some View {
        ZStack {
            Button {
                authState.isProfileBlurViewVisible = false
                authState.isBlurViewVisible = false
            } label: {
                BlurEffect(style: .systemMaterialDark)
            }
            if let user = authState.currentUser {
                VStack {
                    Spacer()
                        .frame(height: 100)
                    
                    Text("SONDR")
                        .font(AuthState.Typography.font_1_bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                        .frame(height: 130)
                    
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
                    
                    Text(user.username)
                        .font(AuthState.Typography.font_1_bold)
                    Text("\(authState.friendCount) \(authState.friendOrFriends)")
                        .font(AuthState.Typography.font_1_bold)
                    
                    Spacer()
                        .frame(height: 60)
                    
                    Button {
                        withAnimation {
                            authState.comingSoonAlert = true
                        }
                    } label: {
                        Text("MILESTONES")
                            .font(AuthState.Typography.font_5_bold)
                    }
                    
                    Spacer()
                        .frame(height: 40)
                    
                    Button {
                        withAnimation {
                            authState.isAddFriendsVisible.toggle()
                        }
                    } label: {
                        Text("ADD FRIENDS")
                            .font(AuthState.Typography.font_5_bold)
                    }
                    .sheet(isPresented: $authState.isAddFriendsVisible) {
                        AddFriends(authState: authState)
                    }
                    
                    Spacer()
                        .frame(height: 40)

                    Button {
                        withAnimation {
                            authState.isSettingsVisible = true
                        }
                    } label: {
                        Text("SETTINGS")
                            .font(AuthState.Typography.font_5_bold)
                    }
                    .sheet(isPresented: $authState.isSettingsVisible) {
                        SettingsView(authState: authState)
                            .presentationDetents([.fraction(4/10)])
                    }
                    
                    Spacer()
                    
                }
                .foregroundColor(.white)
                .task {
                    await authState.friendsCounter()
                }
                .alert("Coming Soon...", isPresented: $authState.comingSoonAlert) {
                    Button("Continue") {
                        authState.comingSoonAlert.toggle()
                    }
                }
            }
        }
    }
}

struct ProfileOptions_Previews: PreviewProvider {
    static var previews: some View {
        return ProfileOptions(authState: AuthState())
    }
}


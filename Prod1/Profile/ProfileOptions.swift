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
        GeometryReader { geometry in
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
                            .frame(height: geometry.size.height * 0.12)
                        
                        Text("SONDR")
                            .font(AuthState.Typography.font_1_bold)
                            .foregroundColor(.white)
                        
                        Spacer()
                            .frame(height: geometry.size.height * 0.15)
                        
                        PhotosPicker(selection: $authState.selectedItem) {
                            if let profileImage = authState.profileImage {
                                profileImage
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width * 0.18, height: geometry.size.width * 0.18)
                                    .clipShape(Circle())
                            } else {
                                Text(user.initial)
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                                    .frame(width: geometry.size.width * 0.18, height: geometry.size.width * 0.18)
                                    .background(Color.gray)
                                    .clipShape(Circle())
                            }
                        }
                        
                        Text(user.username)
                            .font(AuthState.Typography.font_1_bold)
                        Text("\(authState.friendCount) \(authState.friendOrFriends)")
                            .font(AuthState.Typography.font_1_bold)
                        
                        Spacer()
                            .frame(height: geometry.size.height * 0.07)
                        
                        Button {
                            withAnimation {
                                authState.comingSoonAlert = true
                            }
                        } label: {
                            Text("MILESTONES")
                                .font(AuthState.Typography.font_1_bold_sondr)
                        }
                        
                        Spacer()
                            .frame(height: geometry.size.height * 0.05)
                        
                        Button {
                            withAnimation {
                                authState.isAddFriendsVisible.toggle()
                            }
                        } label: {
                            Text("ADD FRIENDS")
                                .font(AuthState.Typography.font_1_bold_sondr)
                        }
                        .sheet(isPresented: $authState.isAddFriendsVisible) {
                            AddFriends(authState: authState)
                        }
                        
                        Spacer()
                            .frame(height: geometry.size.height * 0.05)

                        Button {
                            withAnimation {
                                authState.isSettingsVisible = true
                            }
                        } label: {
                            Text("SETTINGS")
                                .font(AuthState.Typography.font_1_bold_sondr)
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
}

struct ProfileOptions_Previews: PreviewProvider {
    static var previews: some View {
        return ProfileOptions(authState: AuthState())
    }
}


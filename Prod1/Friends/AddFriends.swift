//
//  AddFriends.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 13/06/2024.
//

import SwiftUI
import Combine

struct AddFriends: View {
    @ObservedObject var authState: AuthState
    @State var friend: String = ""
    @State var link: String = ""
    
    func timeFormat(seconds: Int) -> String {
        if seconds >= 3600 {
            let hours = seconds / 3600
            return "\(hours) \(hours == 1 ? "hr" : "hrs")"
        } else if seconds >= 60 {
            let minutes = seconds / 60
            return "\(minutes) \(minutes == 1 ? "min" : "mins")"
        } else {
            return "\(seconds) \(seconds == 1 ? "sec" : "secs")"
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                authState.darkGray.ignoresSafeArea()
                VStack {
                    Spacer()
                        .frame(height: geometry.size.height * 0.025)
                    
                    Text("SONDR")
                        .font(AuthState.Typography.font_1_bold)
                        .foregroundColor(.white)
                        .shadow(radius: 3, x: 3, y: 3)
                    
                    Spacer()
                        .frame(height: geometry.size.height * 0.05)
                    
                    Input(text: $friend,
                          title: "Search for your Friends!",
                          placeHolder: "username/email")
                    .foregroundColor(.white)
                    .onChange(of: friend) { newValue in
                        Task {
                            await authState.searchUsers(query: friend)
                        }
                    }
                    
                    
                    if !friend.isEmpty && !authState.searchResults.isEmpty {
                        List(authState.searchResults.keys.sorted(), id: \.self) { uniqueKey in // Iterate over sorted keys of the dictionary

                            // Extract the username by removing the '_uniqueId...' part
                            let username = uniqueKey.components(separatedBy: "_uniqueId").first ?? uniqueKey
                            
                            HStack {
                                // Display the profile image or a placeholder if not available
                                if let image = authState.profileImageCache[username] {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: geometry.size.width * 0.1, height: geometry.size.width * 0.1)
                                        .clipShape(Circle())
                                } else {
                                    // Fallback to a circle with initial if no image is available
                                    Circle()
                                        .frame(width: geometry.size.width * 0.1, height: geometry.size.width * 0.1)
                                        .foregroundColor(.white)
                                        .overlay(Text(username.first?.uppercased() ?? "").foregroundColor(.black).bold()) // Use the first letter of the username as the initial
                                }
                                
                                // Display the username and its associated value
                                if let value = authState.searchResults[uniqueKey] {
                                    Text("\(username) - \(timeFormat(seconds: value))")
                                        .foregroundColor(.white)
                                        .font(AuthState.Typography.font_4_bold)
                                }
                                
                                Spacer()
                            }
                            .onAppear {
                                Task {
                                    if authState.profileImageCache[username] == nil {
                                        if let image = await authState.retrieveFriendImage(for: username) {
                                            DispatchQueue.main.async {
                                                authState.profileImageCache[username] = image
                                            }
                                        }
                                    }
                                }
                            }
                            .onTapGesture {
                                Task {
                                    await authState.addFriends(withUsername: username)
                                }
                            }
                        }
                        .listStyle(PlainListStyle())
                    }
                    
                    Spacer()
                    
                    ShareLink(item: "Join me on SONDR! Download the app and let's connect: https://apps.apple.com/app/sondr") {
                        ZStack {
                            Rectangle()
                                .frame(width: geometry.size.width * 0.75, height: geometry.size.height * 0.05)
                                .cornerRadius(10)
                                .foregroundColor(.gray)
                            Text("Invite your friends to SONDR")
                                .font(AuthState.Typography.font_4_bold)
                                .foregroundColor(.white)
                        }
                    }
                    
                    Spacer()
                        .frame(height: geometry.size.height * 0.025)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, geometry.size.width * 0.04)
            .alert("User doesn't exist", isPresented: $authState.addFriendsError) {
                Button("Try Again") {
                    authState.addFriendsError = false
                }
            }
            if authState.friendAdded {
                VStack {
                    Text(authState.friendMessage)
                        .padding()
                        .background(Color.white.opacity(0.3))
                        .foregroundColor(.black)
                        .cornerRadius(10)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                withAnimation(.easeOut(duration: 2)) {
                                    authState.friendAdded = false
                                }
                            }
                        }
                }
            }
            }
        }
    }
}

// MARK: Add friends button



#Preview {
    AddFriends(authState: AuthState())
}

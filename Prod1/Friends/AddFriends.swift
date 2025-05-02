//
//  AddFriends.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 13/06/2024.
//

import SwiftUI
import Combine

struct AddFriends: View {
    @EnvironmentObject var viewModel: ViewModel
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
        ZStack {
            viewModel.darkGray.ignoresSafeArea()
            VStack {
                Spacer()
                    .frame(height: 20)
                
                Text("SONDR")
                    .font(.title)
                    .foregroundColor(.white)
                    .shadow(radius: 3, x: 3, y: 3)
                    .fontWeight(.black)
                
                Spacer()
                    .frame(height: 40)
                
                Input(text: $friend,
                      title: "Search for your Friends!",
                      placeHolder: "username/email")
                .foregroundColor(.white)
                .onChange(of: friend) { newValue in
                    Task {
                        await viewModel.searchUsers(query: friend)
                    }
                }
                
                
                if !friend.isEmpty && !viewModel.searchResults.isEmpty {
                    List(viewModel.searchResults.keys.sorted(), id: \.self) { uniqueKey in // Iterate over sorted keys of the dictionary

                        // Extract the username by removing the '_uniqueId...' part
                        let username = uniqueKey.components(separatedBy: "_uniqueId").first ?? uniqueKey
                        
                        HStack {
                            // Display the profile image or a placeholder if not available
                            if let image = viewModel.profileImageCache[username] {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            } else {
                                // Fallback to a circle with initial if no image is available
                                Circle()
                                    .frame(width: 40, height: 40)
                                    .foregroundColor(.white)
                                    .overlay(Text(username.first?.uppercased() ?? "").foregroundColor(.black).bold()) // Use the first letter of the username as the initial
                            }
                            
                            // Display the username and its associated value
                            if let value = viewModel.searchResults[uniqueKey] {
                                Text("\(username) - \(timeFormat(seconds: value))")
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                        }
                        .onAppear {
                            Task {
                                if viewModel.profileImageCache[username] == nil {
                                    if let image = await viewModel.retrieveFriendImage(for: username) {
                                        DispatchQueue.main.async {
                                            viewModel.profileImageCache[username] = image
                                        }
                                    }
                                }
                            }
                        }
                        .onTapGesture {
                            Task {
                                await viewModel.addFriends(withUsername: username)
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
                
                Spacer()
                
                Button {
                    
                } label: {
                    ZStack {
                        Rectangle()
                            .frame(width: 300, height: 40)
                            .cornerRadius(10)
                            .foregroundColor(.gray)
                        Text("Invite your friends to SONDR")
                            .foregroundColor(.white)
                    }
                }
                
                Spacer()
                    .frame(height: 20)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 15)
            .alert("User doesn't exist", isPresented: $viewModel.addFriendsError) {
                Button("Try Again") {
                    viewModel.addFriendsError = false
                }
            }
            if viewModel.friendAdded {
                VStack {
                    Text(viewModel.friendMessage)
                        .padding()
                        .background(Color.white.opacity(0.3))
                        .foregroundColor(.black)
                        .cornerRadius(10)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                withAnimation(.easeOut(duration: 2)) {
                                    viewModel.friendAdded = false
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
    AddFriends()
        .environmentObject(MockViewModel() as ViewModel)
}

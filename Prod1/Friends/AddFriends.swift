//
//  AddFriends.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 13/06/2024.
//

import SwiftUI

struct AddFriends: View {
    @EnvironmentObject var viewModel: ViewModel
    @State var friend: String = ""
    @State var link: String = ""
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
                      title: "Add or search for your Friends!",
                      placeHolder: "username/email")
                .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    // Create Friend Sub-Collection
                    Task {
                        await viewModel.addFriends(withUsername: friend)
                    }
                    viewModel.isAddFriendsVisible = false
                    viewModel.isFriendsVisible = false
                } label: {
                    Text("Add friend")
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
        }
    }
}

// MARK: Add friends button



#Preview {
    AddFriends()
        .environmentObject(MockViewModel() as ViewModel)
}

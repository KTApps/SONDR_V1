//
//  Profile.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 05/07/2024.
//

import SwiftUI

struct ProfileOptions: View {
    @EnvironmentObject var viewModel: ViewModel
    var body: some View {
        ZStack {
            Button {
                viewModel.isProfileBlurViewVisible = false
                viewModel.isBlurViewVisible = false
            } label: {
                BlurEffect(style: .systemMaterialDark)
            }
            if let user = viewModel.currentUser {
                VStack {
                    Button {
                        withAnimation {
                            viewModel.comingSoonAlert = true
                        }
                    } label: {
                        Text(user.initial)
                            .font(.largeTitle)
                            .foregroundColor(.white)
                            .frame(width: 70, height: 70)
                            .background(Color.gray)
                            .clipShape(Circle())
                    }
                    Text(user.username)
                    Text("\(viewModel.friendCount) \(viewModel.friendOrFriends)")
                    
                    Spacer()
                        .frame(height: 60)
                    
                    Button {
                        withAnimation {
                            viewModel.comingSoonAlert = true
                        }
                    } label: {
                        Text("MILESTONES")
                            .font(.title)
                            .fontWeight(.heavy)
                    }
                    
                    Spacer()
                        .frame(height: 40)
                    
                    Button {
                        withAnimation {
                            viewModel.isAddFriendsVisible.toggle()
                        }
                    } label: {
                        Text("ADD FRIENDS")
                            .font(.title)
                            .fontWeight(.heavy)
                    }
                    .sheet(isPresented: $viewModel.isAddFriendsVisible) {
                        AddFriends()
                            .presentationDetents([.fraction(3/10)])
                    }
                    
                    Spacer()
                        .frame(height: 40)

                    Button {
                        withAnimation {
                            viewModel.isSettingsVisible = true
                        }
                    } label: {
                        Text("SETTINGS")
                            .font(.title)
                            .fontWeight(.heavy)
                    }
                    .sheet(isPresented: $viewModel.isSettingsVisible) {
                        SettingsView()
                            .presentationDetents([.fraction(4/10)])
                    }
                }
                .foregroundColor(.white)
                .task {
                    await viewModel.friendsCounter()
                }
                .alert("Coming Soon...", isPresented: $viewModel.comingSoonAlert) {
                    Button("Continue") {
                        viewModel.comingSoonAlert.toggle()
                    }
                }
            }
        }
    }
}

struct ProfileOptions_Previews: PreviewProvider {
    static var previews: some View {
        return ProfileOptions()
            .environmentObject(MockViewModel() as ViewModel)
    }
}


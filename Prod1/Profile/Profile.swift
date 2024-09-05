//
//  Profile.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 05/08/2024.
//

import SwiftUI

struct Profile: View {
    @EnvironmentObject var viewModel: ViewModel
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let user = viewModel.currentUser {
                ZStack {
                    VStack {
                        HStack {
                            Button {
                                withAnimation {
                                    viewModel.isProfileViewVisible = false
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .resizable()
                                    .frame(width: 17, height: 30)
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                                .frame(width: 108)
                            
                            Text("SONDR")
                                .font(.largeTitle)
                                .fontWeight(.heavy)
                            
                            Spacer()
                        }
                        
                        HStack {
                            Button {
                                withAnimation {
                                    viewModel.comingSoonAlert = true
                                }
                            } label: {
                                Text(user.initial)
                                    .font(.largeTitle)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(Color.gray)
                                    .clipShape(Circle())
                            }
                            
                            
                            VStack(alignment: .leading) {
                                Text(user.username)
                                    .font(.callout)
                                    .fontWeight(.bold)
                                Text("\(viewModel.friendCount) \(viewModel.friendOrFriends)")
                                Text("Bio")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Button {
                                    viewModel.comingSoonAlert = true
                                } label:{
                                    Text("Edit")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        
                        Spacer()
                            .frame(height: 20)

                        Text("Posts")
                            .font(.title3)
                            .bold()
                            .underline()
                        
                        Divider()
                            .background(Color.white)
                        
                        Spacer()
                            .frame(height: 10)
                        
                        ZStack {
                            ScrollView {
                                Posts()
                            }
                            
                            VStack {
                                Spacer()
                                    .frame(height: 500)
                                Button {
                                    withAnimation {
                                        viewModel.isAddFriendsVisible.toggle()
                                    }
                                } label:{
                                    ZStack {
                                        Rectangle()
                                            .fill(Color.gray)
                                            .frame(width: 300, height: 50)
                                            .cornerRadius(10)
                                            .shadow(color: Color.gray, radius: 5)
                                        
                                        HStack {
                                            Text("Invite your friends to")
                                            Text("SONDR")
                                                .font(.title3)
                                                .fontWeight(.bold)
                                        }
                                    }
                                }
                                .sheet(isPresented: $viewModel.isAddFriendsVisible) {
                                    AddFriends()
                                        .presentationDetents([.fraction(3/10)])
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .foregroundColor(.white)
                }
            }
        }
    }
}

struct Profile_Previews: PreviewProvider {
    static var previews: some View {
        return Profile()
            .environmentObject(MockViewModel() as ViewModel)
    }
}


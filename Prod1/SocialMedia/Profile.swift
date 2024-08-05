//
//  Profile.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 05/08/2024.
//

import SwiftUI

struct Profile: View {
    @EnvironmentObject var viewModel: ViewModel
    @State var selectedTab: Int = 0
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let user = viewModel.currentUser {
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
                                .frame(width: 23)
                            
                            VStack(alignment: .leading) {
                                Text(user.username)
                                    .font(.callout)
                                    .fontWeight(.bold)
                                Text("\(viewModel.friendCount) \(viewModel.friendOrFriends)")
                            }
                            .foregroundColor(.white)
                            .padding(5)
                            
                            Spacer()
                            
                            Button {
                                withAnimation {
                                    viewModel.comingSoonAlert = true
                                }
                            } label: {
                                Text(user.initial)
                                    .font(.title)
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(Color.gray)
                                    .clipShape(Circle())
                            }
                        }
                        
                        Spacer()
                            .frame(height: 20)
         
                        HStack {
                            Button {
                                selectedTab = 0
                            } label: {
                                Label("Posts", systemImage: "camera")
                            }
                            
                            Spacer()
                                .frame(width: 80)
                            
                            Button {
                                selectedTab = 1
                            } label: {
                                Label("LikedPosts", systemImage: "heart")
                                
                            }
                        }
                        .foregroundColor(.white)
                        
                        Divider()
                            .background(Color.white)
                        
                        ScrollView {
                            switch selectedTab {
                            case 0:
                                Posts()
                            case 1:
                                LikedPosts()
                            default:
                                Posts()
                            }
                        }
                    }
                    .padding()
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


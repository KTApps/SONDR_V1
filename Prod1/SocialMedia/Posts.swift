//
//  Posts.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 05/08/2024.
//

import SwiftUI

struct Posts: View {
    @EnvironmentObject var viewModel: ViewModel
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                ScrollView {
                    
                    // Loop through images and display them
                    ForEach(viewModel.postMap, id: \.self) { post in
                        VStack {
                            Spacer()
                            
                            ZStack(alignment: .topLeading) {
                                Image(uiImage: post.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxHeight: .infinity)
                                    .frame(maxWidth: 395)
                                    .clipped()
                                    .cornerRadius(10)
                                //            MARK: HABIT ARRAY
                                VStack {
                                    ForEach(viewModel.habitDataForDayTimeline[post.id]?.habitIdArray ?? [], id: \.self) { habit in
                                        Text(viewModel.habitDataForDayTimeline[post.id]?.habitIdName[habit] ?? "")
                                            .overlay(
                                                viewModel.habitDataForDayTimeline[post.id]?.isHabitStriked[habit] ?? false ?
                                                Rectangle()
                                                    .frame(height: 3)
                                                    .colorInvert()
                                                    .padding(.horizontal, -10)
                                                : nil
                                            )
                                    }
                                }
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(5)
                                
                                VStack {
                                    Spacer()
                                    HStack {
                                        Button {
                                            viewModel.likePost(postId: post.id)
                                        } label: {
                                            Image(systemName: viewModel.heart ? "heart.fill" : "heart")
                                                .resizable()
                                                .frame(width: 25, height: 23)
                                                .foregroundColor(viewModel.heart ? Color.red : Color.white)
                                        }
                                        
                                        Spacer()
                                            .frame(width: 15)
                                        
                                        Button {
                                            viewModel.postCommentsId = post.id
                                            viewModel.comments.toggle()
                                        } label: {
                                            Image(systemName: "message")
                                                .resizable()
                                                .frame(width: 25, height: 23)
                                                .foregroundColor(.white)
                                        }
                                        .sheet(isPresented: $viewModel.comments) {
                                            Comments()
                                                .presentationDetents([.fraction(3/5)])
                                        }
                                    }
                                    .padding(5)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(5)
                                }
                            }
                            Spacer()
                            
                            Text(post.caption)
                                .font(.title3)
                                .fontWeight(.medium)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .foregroundColor(.white)
                            
                            Spacer()
                            Divider()
                                .background(Color.white)
                        }
                    }
                }
            }
            .onAppear {
                viewModel.retrieveUserPosts()
            }
        }
    }
}

#Preview {
    Posts()
        .environmentObject(MockViewModel() as ViewModel)
}

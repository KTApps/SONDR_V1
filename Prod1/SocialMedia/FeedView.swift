//
//  FeedView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 11/07/2024.
//

import SwiftUI
import Firebase

struct FeedView: View {
    @EnvironmentObject var viewModel: ViewModel
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                Text("APP NAME")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                ScrollView {
                    
                    // Loop through images and display them
                    ForEach(viewModel.postMap, id: \.self) { post in
                        VStack {
                            Spacer()
                            Divider()
                            
                            Spacer()
                            HStack {
                                Text(post.initial)
                                    .font(.title3)
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.gray)
                                    .clipShape(Circle())
                                
                                Text(post.username)
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 5)
                            
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
                                .background(Color.black.opacity(0.2))
                                .cornerRadius(5)
                            }
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
                                }
                                .sheet(isPresented: $viewModel.comments) {
                                    Comments()
                                        .presentationDetents([.fraction(3/5)])
                                }
                                
                                Spacer()
                                    .frame(width: 15)
                                
                                Button {
                                    viewModel.paperplane.toggle()
                                } label: {
                                    Image(systemName: "paperplane")
                                        .resizable()
                                        .frame(width: 25, height: 23)
                                }
                                .sheet(isPresented: $viewModel.paperplane) {
                                    Comments()
                                        .presentationDetents([.fraction(2/5)])
                                }
                                
                                Text(post.caption)
                                    .font(.title3)
                                    .fontWeight(.medium)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .foregroundColor(.white)
                            Spacer()
                        }
                    }
                }
            }
            .onAppear {
                viewModel.retrievePhotos()
            }
        }
    }
}

#Preview {
    FeedView()
        .environmentObject(MockViewModel() as ViewModel)
}


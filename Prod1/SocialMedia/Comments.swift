//
//  messages.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 30/07/2024.
//

import SwiftUI

struct Comments: View {
    @EnvironmentObject var viewModel: ViewModel
    let post: String
    var body: some View {
        ZStack {
            Button(action: {
                withAnimation {
                    viewModel.isPostBlurViewVisible = false
                }
            }) {
                BlurEffect(style: .systemMaterialDark)
            }
            .ignoresSafeArea()
            
            VStack {
                Spacer()
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(viewModel.commentMap[post] ?? []) { comment in
                            Spacer()
                                .frame(height: 20)
                            
                            HStack {
                                Text(comment.initial)
                                    .font(.title)
                                    .foregroundColor(.white)
                                    .frame(width: 45, height: 45)
                                    .background(Color.gray)
                                    .clipShape(Circle())
                                VStack(alignment: .leading) {
                                    Text(comment.username)
                                        .font(.callout)
                                        .fontWeight(.bold)
                                    Text(comment.comment)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding()
                }
                
                Spacer()
                Divider()
                    .foregroundColor(.gray)
                    .frame(height: 30)
                
                ScrollView {
                    ZStack(alignment: .trailing) {
                        if viewModel.comment.isEmpty {
                            Text("Write your comment")
                                .foregroundColor(.gray)
                                .padding(.trailing, 220)
                        }
                        TextField("", text: $viewModel.comment)
                            .foregroundColor(.primary)
                            .padding()

                        if !viewModel.comment.isEmpty {
                            Button {
                                Task {
                                    await viewModel.uploadComment()
                                }
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 15)
                            }
                        }
                    }
                }
                .frame(height: 70)
            }
        }
        .onAppear {
            print("Comments view visability = \(viewModel.comments)")
        }
        .onDisappear {
            print("comments view visability = \(viewModel.comments)")
        }
    }
}

#Preview {
    Comments(post: "1234")
        .environmentObject(MockViewModel() as ViewModel)
}

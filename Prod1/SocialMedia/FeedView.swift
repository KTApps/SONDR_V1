import SwiftUI

struct FeedView: View {
    @EnvironmentObject var viewModel: ViewModel
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                Spacer()
                    .frame(height: 10)
                Text("APP NAME")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                ScrollView {
                    // Loop through images and display them
                    ForEach(viewModel.postMap.indices, id: \.self) { index in
                        Feed(post: $viewModel.postMap[index])
                    }
                }
                .onAppear {
                    Task {
                        await viewModel.retrievePhotos()
                    }
                }
            }
        }
    }
}

struct Feed: View {
    @EnvironmentObject var viewModel: ViewModel
    @Binding var post: PostData
    
    var body: some View {
        VStack {
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
                
                // MARK: HABIT ARRAY
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
                        if let user = viewModel.authRef.currentUser?.uid {
                            let isLiked = post.likes[user] ?? false
                            Button {
                                Task {
                                    await viewModel.likePost(postId: post.id)
                                }
                                post.likes[user] = !(post.likes[user] ?? false)
                            } label: {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .resizable()
                                    .frame(width: 25, height: 23)
                                    .foregroundColor(isLiked ? Color.red : Color.white)
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

#Preview {
    FeedView()
        .environmentObject(MockViewModel() as ViewModel)
}

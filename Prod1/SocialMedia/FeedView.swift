import SwiftUI

struct FeedView: View {
    @StateObject var viewModel: ViewModel
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                Spacer()
                    .frame(height: 10)
                Text("SONDR")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                ScrollView {
                    // Loop through images and display them
                    ForEach(viewModel.postMap.indices, id: \.self) { index in
                        Feed(post: $viewModel.postMap[index])
                    }
                }
            }
            .onAppear {
                viewModel.listenForPhotos()
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
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.gray)
                    .clipShape(Circle())
                
                VStack(alignment: .leading) {
                    Text(post.username)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Text("\(post.habitStreak) Day Streak")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                Spacer()
            }
            .padding(.horizontal, 5)
            
            Spacer()
            
            Image(uiImage: post.image)
                .resizable()
                .scaledToFill()
                .frame(maxHeight: .infinity)
                .frame(maxWidth: 395)
                .clipped()
                .cornerRadius(10)
            
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
                        Text("\(post.likeCount)")
                            .font(.title3)
                            .foregroundColor(.white)
                        
                        Spacer()
                            .frame(width: 5)
                        
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .resizable()
                            .frame(width: 18, height: 18)
                            .foregroundColor(isLiked ? Color.red : Color.white)
                    }
                    
                    Spacer()
                        .frame(width: 15)
                    
                    Button {
                        viewModel.postCommentsId = post.id
                        viewModel.comId = viewModel.postCommentsId
                        viewModel.comments.toggle()
                    } label: {
                        Text("\(post.commentCount)")
                            .font(.title3)
                            .foregroundColor(.white)
                        
                        Spacer()
                            .frame(width: 5)
                        
                        Image(systemName: "message")
                            .resizable()
                            .frame(width: 18, height: 18)
                            .foregroundColor(.white)
                    }
                    .sheet(isPresented: $viewModel.comments) {
                        Comments(post: viewModel.comId)
                            .presentationDetents([.fraction(3/5)])
                    }
                }
                Spacer()
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
        .onAppear {
            if !viewModel.comments {
                viewModel.comId = ""
            }
        }
    }
}

//#Preview {
//    FeedView()
//        .environmentObject(MockViewModel() as ViewModel)
//}

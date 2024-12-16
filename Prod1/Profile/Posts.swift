//
//  Posts.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 05/08/2024.
//

import SwiftUI

struct Posts: View {
    @EnvironmentObject var viewModel: ViewModel
    
    private let adaptiveColumns = [
        GridItem(.adaptive(minimum: 170))
    ]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                ScrollView {
                    LazyVGrid(columns: self.adaptiveColumns, spacing: 25) {
                        // Loop through images and display them
                        ForEach(viewModel.postMap, id: \.self) { post in
                            PostView(post: $viewModel.postMap[viewModel.postMap.firstIndex(of: post)!])
                                .cornerRadius(10)
                                .padding(.horizontal, 5)
                        }
                    }
                }
                .onAppear {
                    Task {
                        await viewModel.retrieveUserPosts()
                    }
                }
            }
        }
    }
}

struct PostView: View {
    @EnvironmentObject var viewModel: ViewModel
    @Binding var post: PostData
    
    var body: some View {
        Image(uiImage: post.image)
            .resizable()
            .scaledToFill()
            .frame(maxHeight: .infinity)
            .frame(maxWidth: 395)
            .clipped()
            .cornerRadius(10)
    }
}

#Preview {
    Posts()
        .environmentObject(MockViewModel() as ViewModel)
}

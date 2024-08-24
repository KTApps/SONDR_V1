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
        VStack {
            
            Input(text: $friend,
                  title: "Search for your Friends!",
                  placeHolder: "username")
            
            Spacer()
                .frame(height: 15)
            
            Input(text: $link,
                  title: "Copy a link to share with your Friends!",
                  placeHolder: "link")
            
            Spacer()
                .frame(height: 15)
            
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
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 15)
    }
}

#Preview {
    AddFriends()
        .environmentObject(MockViewModel() as ViewModel)
}

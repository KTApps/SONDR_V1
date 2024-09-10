//
//  FriendsBar.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 11/06/2024.
//

import SwiftUI
import Charts

struct FriendsBar: View {
    @EnvironmentObject var viewModel: ViewModel
    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Text("Friends")
                        .onTapGesture {
                            withAnimation {
                                viewModel.isFriendsVisible.toggle()
                            }
                        }
                    
                    Spacer()

                    Button {
                        withAnimation {
                            viewModel.isAddFriendsVisible.toggle()
                        }
                    } label: {
                        Text("Add Friends")
                    }
                    .foregroundColor(.white)
                    .sheet(isPresented: $viewModel.isAddFriendsVisible) {
                        AddFriends()
                            .presentationDetents([.fraction(4/10)])
                    }
                }
                .padding(.horizontal, 13)
                
                ScrollView(.horizontal) {
                    HStack(spacing: -30) {
                        ForEach(viewModel.friendsHabitData.keys.sorted(), id: \.self) { friendUsername in
                            VStack(spacing: -20) {
                                ZStack {
                                    OuterFriendsCircle(username: friendUsername, innerRadius: 22, outerRadius: 29, cornerRadius: 1)
                                    InnerFriendsCircle(username: friendUsername, innerRadius: 13, outerRadius: 20, cornerRadius: 1)
                                }
                                Text(friendUsername)
                                    .font(.system(size: 14))
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 5)
                }
                .offset(y: -22)
            }
            .padding(.vertical, 8)
            .task {
                await viewModel.fetchAllFriendsData()
            }
        }
    }
}

struct OuterFriendsCircle: View {
    @EnvironmentObject var authModel: ViewModel
    var username: String
    let innerRadius: MarkDimension
    let outerRadius: MarkDimension
    let cornerRadius: CGFloat
    
    var body: some View {
        Chart(authModel.friendsTaskData[username]?.tasks ?? [], id:\.self) { task in
            SectorMark(
                angle: .value("Time Spent", authModel.friendsTaskData[username]?.taskTimerDictionary[task] ?? 0),
                innerRadius: innerRadius,
                outerRadius: outerRadius,
                angularInset: 1
            )
            .cornerRadius(cornerRadius)
        }
    }
}

struct InnerFriendsCircle: View {
    @EnvironmentObject var authModel: ViewModel
    var username: String
    let innerRadius: MarkDimension
    let outerRadius: MarkDimension
    let cornerRadius: CGFloat

    var body: some View {
        Chart(authModel.friendsHabitData[username]?.habitIdArray ?? [""], id:\.self) { habit in
            SectorMark(
                angle: .value("isTicked", 1),
                innerRadius: innerRadius,
                outerRadius: outerRadius,
                angularInset: 1
            )
            .foregroundStyle(authModel.friendColorReturn(value: habit, username: username))
            .cornerRadius(cornerRadius)
        }
    }
}

struct FriendsBar_Previews: PreviewProvider {
    static var previews: some View {
        return FriendsBar()
            .environmentObject(MockViewModel() as ViewModel)
    }
}

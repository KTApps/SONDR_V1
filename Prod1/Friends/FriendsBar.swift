//
//  FriendsBar.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 11/06/2024.
//

import SwiftUI
import Charts

struct FriendsBar: View {
    @ObservedObject var authState: AuthState
    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Button {
                        withAnimation {
                            authState.isAddFriendsVisible.toggle()
                        }
                    } label: {
                        Text("Add Friends")
                    }
                    .foregroundColor(.white)
                    .sheet(isPresented: $authState.isAddFriendsVisible) {
                        AddFriends(authState: authState)
                            .onDisappear {
                                authState.searchResults = [:]
                            }
                    }
                    Spacer()
                }
                .padding(.horizontal, 13)
                
                ScrollView(.horizontal) {
                    HStack(spacing: -30) {
                        ForEach(authState.friendsHabitData.keys.sorted(), id: \.self) { friendUsername in
                            VStack(spacing: -15) {
                                ZStack {
                                    OuterFriendsCircle(authState: authState,
                                                       username: friendUsername,
                                                       innerRadius: 22,
                                                       outerRadius: 29,
                                                       cornerRadius: 1)
                                    InnerFriendsCircle(authState: authState,
                                                       username: friendUsername,
                                                       innerRadius: 12,
                                                       outerRadius: 19,
                                                       cornerRadius: 1)
                                }
                                Text(friendUsername)
                                    .font(.system(size: 14))
                            }
                        }
                        Spacer()
                    }
                }
                .offset(y: -22)
            }
            .padding(.vertical, 8)
        }
    }
}

struct OuterFriendsCircle: View {
    @ObservedObject var authState: AuthState
    var username: String
    let innerRadius: MarkDimension
    let outerRadius: MarkDimension
    let cornerRadius: CGFloat
    
    var body: some View {
        if let tasks = authState.friendsTaskData[username]?.tasks,
           let taskTimers = authState.friendsTaskData[username]?.taskTimerDictionary,
           !tasks.isEmpty,
           !taskTimers.isEmpty {
            // Render the chart if there are tasks and timers
            Chart(tasks, id: \.self) { task in
                SectorMark(
                    angle: .value("Time Spent", taskTimers[task] ?? 0),
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    angularInset: 1
                )
                .cornerRadius(cornerRadius)
            }
        } else {
            Chart(authState.placeholderTasks, id: \.self) { task in
                SectorMark(
                    angle: .value("Time Spent", task),
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    angularInset: 1
                )
                .cornerRadius(cornerRadius)
            }
            .foregroundColor(.gray)
            .opacity(0.3)
        }
    }
}

struct InnerFriendsCircle: View {
    @ObservedObject var authState: AuthState
    var username: String
    let innerRadius: MarkDimension
    let outerRadius: MarkDimension
    let cornerRadius: CGFloat

    var body: some View {
        if let habits = authState.friendsHabitData[username]?.habitIdArray, !habits.isEmpty {
            Chart(habits, id: \.self) { habit in
                SectorMark(
                    angle: .value("isTicked", 1),
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    angularInset: 1
                )
                .foregroundStyle(authState.friendColorReturn(value: habit, username: username))
                .cornerRadius(cornerRadius)
            }
        } else {
            Chart(authState.placeholderTasks, id: \.self) { task in
                SectorMark(
                    angle: .value("Time Spent", task),
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    angularInset: 1
                )
                .cornerRadius(cornerRadius)
            }
            .foregroundColor(.gray)
            .opacity(0.3)
        }
    }
}

struct FriendsBar_Previews: PreviewProvider {
    static var previews: some View {
        return FriendsBar(authState: AuthState())
    }
}

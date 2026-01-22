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
    
    // Fixed sizes for circles
    private let circleInnerRadius: CGFloat = 22
    private let circleOuterRadius: CGFloat = 29
    private let innerCircleInnerRadius: CGFloat = 12
    private let innerCircleOuterRadius: CGFloat = 19
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "Add Friends" button
            HStack {
                Button {
                    withAnimation {
                        authState.isAddFriendsVisible.toggle()
                    }
                } label: {
                    Text("Add Friends")
                        .font(AuthState.Typography.font_4_bold)
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
            .padding(.top, 12)
            .padding(.leading, 14)
            
            // Friend circles
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -30) {
                    ForEach(authState.friendsHabitData.keys.sorted(), id: \.self) { friendUsername in
                        VStack(spacing: 0) {
                            ZStack {
                                OuterFriendsCircle(authState: authState,
                                                   username: friendUsername,
                                                   innerRadius: MarkDimension(floatLiteral: circleInnerRadius),
                                                   outerRadius: MarkDimension(floatLiteral: circleOuterRadius),
                                                   cornerRadius: 1)
                                InnerFriendsCircle(authState: authState,
                                                   username: friendUsername,
                                                   innerRadius: MarkDimension(floatLiteral: innerCircleInnerRadius),
                                                   outerRadius: MarkDimension(floatLiteral: innerCircleOuterRadius),
                                                   cornerRadius: 1)
                            }
                            Text(friendUsername)
                                .font(AuthState.Typography.font_4_bold)
                                .padding(.top, -30)
                        }
                    }
                }
            }
            .padding(.top, -24)
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

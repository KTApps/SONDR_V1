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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
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
                    .padding(.horizontal, geometry.size.width * 0.035)
                    .padding(.top, 8)  // Fixed: consistent visual separation from top
                    
                    //Spacer().frame(height: 1)  // Fixed: consistent gap between text and circles
                    
                    ScrollView(.horizontal) {
                        HStack(spacing: geometry.size.width * -0.08) {
                            ForEach(authState.friendsHabitData.keys.sorted(), id: \.self) { friendUsername in
                                VStack(spacing: geometry.size.width * -0.05) {
                                    ZStack {
                                        OuterFriendsCircle(authState: authState,
                                                           username: friendUsername,
                                                           innerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.055),
                                                           outerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.073),
                                                           cornerRadius: 1)
                                        InnerFriendsCircle(authState: authState,
                                                           username: friendUsername,
                                                           innerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.03),
                                                           outerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.048),
                                                           cornerRadius: 1)
                                    }
                                    Text(friendUsername)
                                        .font(AuthState.Typography.font_4_bold)
                                }
                            }
                            Spacer()
                        }
                    }
                    .padding(.top, -8)  // Pull circles up closer to "Add Friends" text
                    
                    Spacer()
                }
            }
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

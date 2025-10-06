//
//  ContentView.swift
//  Prod1
//
//  Created by Tanaka Bere on 10/02/2024.
//

import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject var authState: AuthState
    @State var isShowingCumTime: Bool = false
    @State var playButton: String = "play.fill"
    
    var body: some View {
//        MARK: ZStack for BlurView
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                VStack {
                    
                    // MARK: GROUP 1
                    HStack {
                        Spacer()
                        
                        Button {
                            withAnimation {
                                authState.isFriendsVisible.toggle()
                                authState.isTaskDropDownVisible = false
                                authState.selectedTask = nil
                            }
                        } label: {
                            Image(systemName: "person.fill")
                                .resizable()
                                .frame(width: geometry.size.width * 0.06, height: geometry.size.height * 0.03)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                            .frame(width: geometry.size.width * 0.05)
                        
                        Button {
                            withAnimation {
                                authState.isProfileBlurViewVisible = true
                                authState.isFriendsVisible = false
                                authState.isTaskDropDownVisible = false
                                authState.selectedTask = nil
                            }
                        } label: {
                            Image(systemName: "gear")
                                .resizable()
                                .frame(width: geometry.size.width * 0.06, height: geometry.size.height * 0.033)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                                        
                    // MARK: GROUP 2
                    VStack {
                        HStack{
                            Spacer()
                                .frame(width: geometry.size.width * 0.04)
                            Text(authState.taskName)
                                .font(AuthState.Typography.font_1_bold)
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: geometry.size.width * 0.04))
                        }
                        .bold()
                        .foregroundColor(.white)
                        .onTapGesture {
                            withAnimation {
                                authState.isTaskDropDownVisible.toggle()
                                authState.selectedTask = nil
                            }
                        }
                        
                        Spacer()
                            .frame(height: geometry.size.width * 0.02)
                        
                        Button(action: {
                            authState.isTimerOn.toggle()
                            if authState.isTimerOn {
                                playButton = "pause.fill"
                                authState.timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
                            } else {
                                playButton = "play.fill"
                                authState.timer.upstream.connect().cancel()
                                authState.updateTaskTimerInFirestore(taskName: authState.taskName, 
                                                                     monthlyProgressCount: authState.cumulativeTime,
                                                                     timerCount: authState.taskTime)
                                authState.progressPercentage()
                                authState.newTimeCalc()
                                authState.cumulativeProgress()
                            }
                        }) {
                            HStack {
                                Spacer()
                                    .frame(width: geometry.size.width * 0.04)
                                
                                Text(isShowingCumTime ? "\(authState.formattedCumulativeTime)" : "\(authState.formattedTaskTime)")
                                    .onReceive(authState.timer) { time in
                                        if authState.isTimerOn {
                                            authState.taskTime += 1
                                            authState.cumulativeTime += 1
                                            authState.cumulativeProg += 1
                                            var nilCoalescingOp = authState.taskTimerDictionary[authState.taskName] ?? 0
                                            nilCoalescingOp += 1
                                            var nilCoalescingOp2 = authState.monthlyProgressTimerDictionary[authState.taskName] ?? 0
                                            nilCoalescingOp2 += 1
                                        }
                                        if authState.taskName == "Task" {
                                            authState.taskTime = 0
                                            authState.cumulativeTime = authState.cumulativeProg
                                        }
                                    }
                                Image(systemName: playButton)
                                    .font(AuthState.Typography.font_3_bold)
                            }
                        }
                        .foregroundColor(.white)
                        .font(AuthState.Typography.font_3_bold)
                    }
                        
                    Spacer()
                        .frame(height: geometry.size.height * 0.03)
                    
                    // MARK: GROUP 3

                    VStack {
                        ZStack {
                            
                            OuterCircle(authState: authState, 
                                        innerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.30),
                                        outerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.36),
                                        cornerRadius: 1)
                            
                            if let habits = authState.habitData?.habitIdArray, !habits.isEmpty {
                                Chart(habits, id:\.self) { habit in
                                    SectorMark(
                                        angle: .value("isTicked", 1),
                                        innerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.20),
                                        outerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.29),
                                        angularInset: 1
                                    )
                                    .foregroundStyle(authState.colorReturn(value: habit))
                                    .cornerRadius(1)
                                }
                                .frame(width: geometry.size.width * 0.51, height: geometry.size.width * 0.51)
                                .onTapGesture {
                                    withAnimation {
                                        authState.isBlurViewVisible = true
                                        authState.isFriendsVisible = false
                                    }
                                    authState.weekDayIndexCounter = authState.weekdayIndex(forDayOfYear: authState.currentDayOfYear, inYear: authState.currentYear) ?? 0
                                    authState.currentDayOfWeek = authState.currentDayOfYear
                                }
                                .gesture(
                                    DragGesture()
                                        .onEnded { value in
                                            withAnimation {
                                                if value.translation.width < -50 {
                                                    // Swiped left, show cumulative time
                                                    isShowingCumTime = true
                                                } else if value.translation.width > 50 {
                                                    // Swiped right, show task time
                                                    isShowingCumTime = false
                                                }
                                            }
                                        }
                                )
                            } else {
                                Chart(authState.placeholderTasks, id:\.self) { habit in
                                    SectorMark(
                                        angle: .value("isTicked", 1),
                                        innerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.19),
                                        outerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.27),
                                        angularInset: 1
                                    )
                                    .foregroundStyle(.gray)
                                    .opacity(0.3)
                                    .cornerRadius(1)
                                }
                                .frame(width: geometry.size.width * 0.51, height: geometry.size.width * 0.51)
                                .onTapGesture {
                                    withAnimation {
                                        authState.isBlurViewVisible = true
                                        authState.isFriendsVisible = false
                                        authState.selectedTask = nil
                                    }
                                    authState.weekDayIndexCounter = authState.weekdayIndex(forDayOfYear: authState.currentDayOfYear, inYear: authState.currentYear) ?? 0
                                    authState.currentDayOfWeek = authState.currentDayOfYear
                                }
                                .gesture(
                                    DragGesture()
                                        .onEnded { value in
                                            withAnimation {
                                                if value.translation.width < -50 {
                                                    // Swiped left, show cumulative time
                                                    isShowingCumTime = true
                                                } else if value.translation.width > 50 {
                                                    // Swiped right, show task time
                                                    isShowingCumTime = false
                                                }
                                            }
                                        }
                                )
                            }
                        
                            VStack {
                                let task = authState.selectedTask ?? ""
                                
                                Text(task)
                                    .font(AuthState.Typography.font_1_bold)
                                Text(isShowingCumTime ? authState.monthlyTime(for: task) : authState.dailyTime(for: task))
                                    .font(AuthState.Typography.font_3_bold)
                                    .transition(.slide)
                                    .animation(.easeInOut, value: isShowingCumTime)
                                Text(isShowingCumTime ? "\(authState.month)" : "Today")
                                    .font(AuthState.Typography.font_4_bold)
                                    .transition(.slide)
                                    .animation(.easeInOut, value: isShowingCumTime)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // MARK: GROUP 4
                    VStack{
                        /*
                        HStack{
                            Text("Last 10 Days")
                                .font(AuthState.Typography.font_3_bold)
                            Spacer()
                        }
                        */
                        Spacer()
                            .frame(height: 47)
                        ZStack{
                            RoundedRectangle(cornerRadius: 10)
                                .foregroundColor(authState.darkGray)
                                .frame(width: geometry.size.width * 0.92, height: geometry.size.height * 0.27)
                            
                            VStack {
                                Last10Days(authState: authState)
                                
                                Spacer()
                                
                                Button(action: {
                                    authState.isViewYourProgressVisible = true
                                    authState.isFriendsVisible = false
                                    authState.isTaskDropDownVisible = false
                                    authState.selectedTask = nil
                                }) {
                                    ZStack {
                                        /*
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(lineWidth: geometry.size.width * 0.002)
                                            .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.04)
                                        */
                                        Text("View Your Progress")
                                            .font(AuthState.Typography.font_2_light)
                                    }
                                    .foregroundColor(.white)
                                }
                            }
                            .padding(.vertical, geometry.size.height * 0.05)
                            .sheet(isPresented: $authState.isViewYourProgressVisible) {
                                CalendarView(authState: authState)
                            }
                        }
                    }
                }
                .padding(.horizontal, geometry.size.width * 0.04)
                .padding(.vertical, geometry.size.height * 0.05)
                .preferredColorScheme(.dark)
                .onAppear {
                    Task {
                        await authState.listenForUser()
                        let documentTitle = "\(authState.currentYear)\(authState.currentDayOfWeek)"
                        await authState.listenForCircleData(document: documentTitle)
                    }
                }
                
                //            MARK: BlurView Button
                if authState.isBlurViewVisible {
                    withAnimation {
                        HabitTracker(authState: authState)
                            .ignoresSafeArea()
                    }
                }
                if authState.isProfileBlurViewVisible {
                    withAnimation {
                        ProfileOptions(authState: authState)
                            .ignoresSafeArea()
                    }
                }
    //                    MARK: TASK DROP DOWN ZStack
                ZStack{
                    RoundedRectangle(cornerRadius: 10)
                        .foregroundColor(authState.darkGray)
                        .padding(.horizontal, geometry.size.width * 0.04)
                    
                    ProgressBar(authState: authState)
                        .padding(.horizontal, geometry.size.width * 0.04)
                }
                .frame(height: authState.isTaskDropDownVisible ? geometry.size.height * 0.48 : 0) // Control Transition of Height
                .offset(y: authState.isTaskDropDownVisible ? geometry.size.height * 0.14 : geometry.size.height * 0.13) // Control Transition of DropDown
                
                ZStack{
                    RoundedRectangle(cornerRadius: 10)
                        .foregroundColor(authState.darkGray)
                        .padding(.horizontal, geometry.size.width * 0.04)
                    
                    FriendsBar(authState: authState)
                        .padding(.horizontal, geometry.size.width * 0.04)
                }
                .frame(height: authState.isFriendsVisible ? geometry.size.height * 0.17 : 0) // Control Transition of Height
                .offset(y: authState.isFriendsVisible ? geometry.size.height * 0.09 : geometry.size.height * 0.08) // Control Transition of DropDown
                .alert("Congrats, youv've completed the milestone. Your next milestone is in 100 seconds", isPresented: $authState.maxTimeAlert) {
                    Button("Continue") {
                        authState.maxTimeAlert.toggle()
                        authState.updateTaskDecimalDict()
                    }
                }
            }
        }
    }
}
        
        
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        return ContentView(authState: AuthState())
    }
}

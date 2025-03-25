//
//  ContentView.swift
//  Prod1
//
//  Created by Tanaka Bere on 10/02/2024.
//

import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject var viewModel: ViewModel
    @State var isShowingCumTime: Bool = false
    
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
                            Task {
                                await viewModel.fetchAllFriendsData()
                            }
                            withAnimation {
                                viewModel.isFriendsVisible.toggle()
                                viewModel.isTaskDropDownVisible = false
                                viewModel.selectedTask = nil
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
                            Task {
                                await viewModel.fetchAllFriendsData()
                            }
                            withAnimation {
                                viewModel.isProfileBlurViewVisible = true
                                viewModel.isFriendsVisible = false
                                viewModel.isTaskDropDownVisible = false
                                viewModel.selectedTask = nil
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
                                .frame(width: geometry.size.width * 0.03)
                            Text(viewModel.taskName)
                                .font(.system(size: geometry.size.width * 0.06))
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: geometry.size.width * 0.04))
                        }
                        .bold()
                        .foregroundColor(.white)
                        .onTapGesture {
                            withAnimation {
                                viewModel.isTaskDropDownVisible.toggle()
                                viewModel.selectedTask = nil
                            }
                        }
                        
                        Spacer()
                            .frame(height: geometry.size.width * 0.01)
                        
                        Button(action: {
                            viewModel.isTimerOn.toggle()
                            if viewModel.isTimerOn {
                                viewModel.timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
                            } else {
                                viewModel.timer.upstream.connect().cancel()
                                viewModel.progressPercentage()
                                viewModel.newTimeCalc()
                                viewModel.cumulativeProgress()
                            }
                        }) {
                            Text(isShowingCumTime ? "\(viewModel.formattedCumulativeTime)" : "\(viewModel.formattedTaskTime)")
                                .onReceive(viewModel.timer) { time in
                                    if viewModel.isTimerOn {
                                        viewModel.taskTime = viewModel.taskTimer() ?? 0
                                        // Update cumulative progress periodically during timer execution
                                        viewModel.updateCumulativeProgressPeriodically()
                                    }
                                    if viewModel.taskName == "Task" {
                                        viewModel.taskTime = 0
                                        viewModel.cumulativeTime = viewModel.cumulativeProg
                                    }
                                }
                        }
                        .foregroundColor(.white)
                        .font(.system(size: geometry.size.width * 0.06))
                        .bold()
                    }
                        
                    Spacer()
                        .frame(height: geometry.size.height * 0.03)
                    
                    // MARK: GROUP 3

                    VStack {
                        ZStack {
                            
                            OuterCircle(innerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.29), outerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.4), cornerRadius: 1)
                            
                            if let habits = viewModel.habitData?.habitIdArray, !habits.isEmpty {
                                Chart(habits, id:\.self) { habit in
                                    SectorMark(
                                        angle: .value("isTicked", 1),
                                        innerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.19),
                                        outerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.27),
                                        angularInset: 1
                                    )
                                    .foregroundStyle(viewModel.colorReturn(value: habit))
                                    .cornerRadius(1)
                                }
                                .frame(width: geometry.size.width * 0.51, height: geometry.size.width * 0.51)
                                .onTapGesture {
                                    withAnimation {
                                        viewModel.isBlurViewVisible = true
                                        viewModel.isFriendsVisible = false
                                    }
                                    viewModel.weekDayIndexCounter = viewModel.weekdayIndex(forDayOfYear: viewModel.currentDayOfYear, inYear: viewModel.currentYear) ?? 0
                                    viewModel.currentDayOfWeek = viewModel.currentDayOfYear
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
                                Chart(viewModel.placeholderTasks, id:\.self) { habit in
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
                                        viewModel.isBlurViewVisible = true
                                        viewModel.isFriendsVisible = false
                                        viewModel.selectedTask = nil
                                    }
                                    viewModel.weekDayIndexCounter = viewModel.weekdayIndex(forDayOfYear: viewModel.currentDayOfYear, inYear: viewModel.currentYear) ?? 0
                                    viewModel.currentDayOfWeek = viewModel.currentDayOfYear
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
                        
                            VStack{
                                Text(viewModel.selectedTask ?? "")
                                    .font(.system(size: geometry.size.width * 0.05))
                                Text(isShowingCumTime ? "\(viewModel.cumulativeProg) Seconds" : "\(viewModel.taskTime) Seconds")
                                    .font(.system(size: geometry.size.width * 0.05))
                                    .transition(.slide)
                                    .animation(.easeInOut, value: isShowingCumTime)
                                Text(isShowingCumTime ? "\(viewModel.month)" : "Today")
                                    .font(.system(size: geometry.size.width * 0.05))
                                    .transition(.slide)
                                    .animation(.easeInOut, value: isShowingCumTime)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // MARK: GROUP 4
                    VStack{
                        HStack{
                            Text("Last 10 Days")
                                .font(.system(size: geometry.size.width * 0.05))
                                .fontWeight(.bold)
                            Spacer()
                        }
                        
                        ZStack{
                            RoundedRectangle(cornerRadius: 10)
                                .foregroundColor(viewModel.darkGray)
                                .frame(width: geometry.size.width * 0.92, height: geometry.size.height * 0.27)
                            
                            VStack {
                                Last10Days()
                                
                                Spacer()
                                
                                Button(action: {
                                    viewModel.isViewYourProgressVisible = true
                                    viewModel.isFriendsVisible = false
                                    viewModel.isTaskDropDownVisible = false
                                    viewModel.selectedTask = nil
                                }) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(lineWidth: geometry.size.width * 0.002)
                                            .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.04)
                                        
                                        Text("View Your Progress")
                                            .font(.system(size: geometry.size.width * 0.04))
                                            .fontWeight(.bold)
                                    }
                                    .foregroundColor(.white)
                                }
                            }
                            .padding(.vertical, geometry.size.height * 0.05)
                            .sheet(isPresented: $viewModel.isViewYourProgressVisible) {
                                CalendarView()
                            }
                        }
                    }
                }
                .padding(.horizontal, geometry.size.width * 0.04)
                .padding(.vertical, geometry.size.height * 0.05)
                .preferredColorScheme(.dark)
                .onAppear {
                    Task {
                        await viewModel.listenForUser()
                        await viewModel.listenForCircleData(dayOfYear: viewModel.currentDayOfWeek)
                    }
                }
                
                //            MARK: BlurView Button
                if viewModel.isBlurViewVisible {
                    withAnimation {
                        HabitTracker()
                            .ignoresSafeArea()
                    }
                }
                if viewModel.isProfileBlurViewVisible {
                    withAnimation {
                        ProfileOptions()
                            .ignoresSafeArea()
                    }
                }
    //                    MARK: TASK DROP DOWN ZStack
                ZStack{
                    RoundedRectangle(cornerRadius: 10)
                        .foregroundColor(viewModel.darkGray)
                        .padding(.horizontal, geometry.size.width * 0.04)
                    
                    ProgressBar()
                        .padding(.horizontal, geometry.size.width * 0.04)
                }
                .frame(height: viewModel.isTaskDropDownVisible ? geometry.size.height * 0.48 : 0) // Control Transition of Height
                .offset(y: viewModel.isTaskDropDownVisible ? geometry.size.height * 0.14 : geometry.size.height * 0.13) // Control Transition of DropDown
                
                ZStack{
                    RoundedRectangle(cornerRadius: 10)
                        .foregroundColor(viewModel.darkGray)
                        .padding(.horizontal, geometry.size.width * 0.04)
                    
                    FriendsBar()
                        .padding(.horizontal, geometry.size.width * 0.04)
                }
                .frame(height: viewModel.isFriendsVisible ? geometry.size.height * 0.17 : 0) // Control Transition of Height
                .offset(y: viewModel.isFriendsVisible ? geometry.size.height * 0.09 : geometry.size.height * 0.08) // Control Transition of DropDown
                .alert("Congrats, youv've completed the milestone. Your next milestone is in 100 seconds", isPresented: $viewModel.maxTimeAlert) {
                    Button("Continue") {
                        viewModel.maxTimeAlert.toggle()
                        viewModel.updateTaskDecimalDict()
                    }
                }
            }
        }
    }
}
        
        
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        return ContentView()
            .environmentObject(MockViewModel() as ViewModel)
    }
}

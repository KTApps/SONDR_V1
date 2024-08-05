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
    
    var body: some View {
//        MARK: ZStack for BlurView
        ZStack {
            Color.black.ignoresSafeArea()
            VStack{
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .frame(height: 0)
                        .foregroundColor(.black)
                    
                    HStack {
                        //                MARK: FRIENDS BUTTON
                        Image(systemName: "person.fill")
                            .resizable()
                            .foregroundColor(.gray)
                            .frame(width: 25, height: 25)
                        
                        Spacer()
                            .frame(width: 20)
                        
                        //                MARK: SETTINGS BUTTON
                        Button {
                            withAnimation {
                                viewModel.isProfileBlurViewVisible = true
                            }
                        } label: {
                            Image(systemName: "gear")
                                .resizable()
                        }
                        .foregroundColor(.gray)
                        .frame(width: 25, height: 25)
                    }
                }
                .offset(x: 150)
                .onTapGesture {
                    withAnimation {
                        Task {
                            await viewModel.fetchAllFriendsData()
                        }
                        viewModel.isFriendsVisible.toggle()
                    }
                }
                
                //                MARK: TASK TITLE & TASK DROP DOWN ZStack
                ZStack{
                    
                    //                    MARK: TASK TITLE ZStack
                    ZStack{
                        RoundedRectangle(cornerRadius: 10)
                            .frame(height: 0)
                            .foregroundColor(.black)
                        HStack{
                            Text(viewModel.taskName)
                                .font(.largeTitle)
                            
                            Image(systemName: "chevron.down")
                        }
                        .bold()
                        .foregroundColor(.white)
                    }
                    .offset(y: 10)
                    .onTapGesture {
                        withAnimation {
                            viewModel.isTaskDropDownVisible.toggle()
                        }
                    }
                }
                .zIndex(1)
                .padding(.horizontal, 10)
                
                //                            MARK: Timer Button
                Button(action: {
                    viewModel.isTimerOn.toggle()
                    if viewModel.isTimerOn {
                        viewModel.timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
                    } else {
                        viewModel.timer.upstream.connect().cancel()
                        viewModel.progressPercentage()
                        viewModel.newTimeCalc()
                    }
                }) {
                    Text("\(viewModel.formattedTaskTime)")
                        .onReceive(viewModel.timer) { time in
                            if viewModel.isTimerOn {
                                viewModel.taskTime = viewModel.taskTimer() ?? 0
                            }
                        }
                }
                .foregroundColor(.white)
                .font(.title)
                .bold()
                .offset(x: -5, y: 15)
                
                //                            MARK: CIRCLE ZStack
                ZStack{
                    
                    //                                MARK: OUTER CIRCLE
                    Circle()
                        .stroke(lineWidth: 25)
                        .opacity(0.3)
                        .foregroundColor(.gray)
                        .frame(width: 320, height: 300)
                    
                    OuterCircle(innerRadius: 140, outerRadius: 170, cornerRadius: 5)
                    
                    //                                MARK: INNER CIRCLE Button
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 20)
                            .opacity(0.3)
                            .foregroundColor(.gray)
                            .frame(height: 200)
                        Chart(viewModel.habitData?.habitIdArray ?? [""], id:\.self) { habit in
                            SectorMark(
                                angle: .value("isTicked", 1),
                                innerRadius: 90,
                                outerRadius: 120,
                                angularInset: 1
                            )
                            .foregroundStyle(viewModel.colorReturn(value: habit))
                        }
                        .frame(width: 220, height: 220)
                        .onTapGesture {
                            withAnimation {
                                viewModel.isBlurViewVisible = true
                            }
                            viewModel.weekDayIndexCounter = viewModel.weekdayIndex(forDayOfYear: viewModel.currentDayOfYear, inYear: viewModel.currentYear) ?? 0
                            viewModel.currentDayOfWeek = viewModel.currentDayOfYear
                        }
                        VStack{
                            Text("\(viewModel.taskTime) Seconds")
                                .font(.title2)
                            Text("Today")
                                .font(.title3) // placeholder for date
                        }
                    }
                }
                
                //                            MARK: LAST 10 DAYS BLOCK
                VStack{
                    HStack{
                        Text("Last 10 Days")
                            .font(.title3)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    
                    //                                MARK: VIEW YOUR PROGRESS Rectangle
                    ZStack{
                        RoundedRectangle(cornerRadius: 10)
                            .frame(height: 200)
                            .foregroundColor(viewModel.darkGray)
                            .padding(.horizontal, 7)
                        
                        //                                    MARK: VIEW YOUR PROGRESS Button
                        VStack {
                            Last10Days()
                            
                            Spacer()
                                .frame(height: 13)
                            
                            Button(action: {
                                viewModel.isViewYourProgressVisible = true
                            }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(lineWidth: 1)
                                        .frame(width: 210, height: 40)
                                    Text("View Your Progress")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(.white)
                            }
                        }
                        .sheet(isPresented: $viewModel.isViewYourProgressVisible) {
                            ViewYourProgress()
                                .presentationDetents([.fraction(6.7/10)])
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
            
            //            MARK: BlurView Button
            if viewModel.isBlurViewVisible {
                withAnimation {
                    HabitTracker()
                        .ignoresSafeArea()
                }
            }
            if viewModel.isProfileBlurViewVisible {
                withAnimation {
                    Profile()
                        .ignoresSafeArea()
                }
            }
//                    MARK: TASK DROP DOWN ZStack
            ZStack{
                RoundedRectangle(cornerRadius: 10)
                    .foregroundColor(viewModel.darkGray)
                    .padding(.horizontal, 5)
                
                CustomProgressBar()
            }
            .frame(height: viewModel.isTaskDropDownVisible ? 410 : 0) // Control Transition of Height
            .offset(y: viewModel.isTaskDropDownVisible ? -80 : -290) // Control Transition of DropDown
            
            ZStack{
                RoundedRectangle(cornerRadius: 10)
                    .foregroundColor(viewModel.darkGray)
                    .padding(.horizontal, 5)
                
                FriendsBar()
            }
            .frame(height: viewModel.isFriendsVisible ? 125 : 0) // Control Transition of Height
            .offset(y: viewModel.isFriendsVisible ? -285 : -350) // Control Transition of DropDown
            .alert("Congrats, youv've completed the milestone. Your next milestone is in 100 seconds", isPresented: $viewModel.maxTimeAlert) {
                Button("Continue") {
                    viewModel.maxTimeAlert.toggle()
                }
            }
        }
    }
}
        
        
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        let authModel = AuthViewModel() // Create an instance of AuthViewModel
//        authModel.currentUser = UserObject(id: "1",
//                                           username: "NameExample",
//                                           email: "name@example.com") // Set a dummy user
//        return ContentView()
//            .environmentObject(authModel) // Inject authViewModel as environment object
//    }
//}

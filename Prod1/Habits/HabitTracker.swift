//
//  HabitTracker.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 16/02/2024.
//

import SwiftUI
import Firebase
import FirebaseFirestoreSwift

struct HabitTracker: View {
    @EnvironmentObject var viewModel: AuthState
        
    var body: some View {
        ZStack {
            Button(action: {
                viewModel.isBlurViewVisible = false
            }) {
                BlurEffect(style: .systemMaterialDark)
            }
            VStack {
                Spacer()
                    .frame(height: 70)
                
                Text("SONDR")
                    .font(.title)
                    .shadow(radius: 3, x: 3, y: 3)
                    .fontWeight(.black)
                
                Spacer()
                    .frame(height: 30)
                
    //            MARK: WEEKDAY HStack
                HStack {
                    
    //                MARK: LEFT CHEVRON
                    Button(action: {
                        if viewModel.weekDayIndexCounter != 0 {
                            viewModel.weekDayIndexCounter -= 1
                        } else {
                            viewModel.weekDayIndexCounter += 6
                        }
                        
                        viewModel.weekdayMinus()
                                            
                    }) {
                        Image(systemName: "chevron.left")
                            .shadow(radius: 3, x: 3, y: 3)
                    }
                    .padding(20)
                    
                    Spacer()
                    
    //                MARK: WEEKDAY ARRAY
                    Text(viewModel.weekDay[viewModel.weekDayIndexCounter])
                        .font(.custom("medium Header", size: 25))
                        .shadow(radius: 3, x: 3, y: 3)
                        .fontWeight(.black)
                    
                    Spacer()
                    
    //                MARK: RIGHT CHEVRON
                    Button(action: {
                        if viewModel.weekDayIndexCounter != 6 {
                            viewModel.weekDayIndexCounter += 1
                        } else {
                            viewModel.weekDayIndexCounter = 0
                        }
                        
                        viewModel.weekdayPlus()
                        
                    }) {
                        Image(systemName: "chevron.right")
                            .shadow(radius: 3, x: 3, y: 3)
                    }
                    .padding(20)
                }
                .font(.custom("Big title", size: 35))
                .fontWeight(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, -10)
                
                Text("Day \(viewModel.habitStreak)")
                    .font(.callout)
                
                Spacer()
                    .frame(height: 70)
                
    //            MARK: HABIT ARRAY
                let documentTitle = "\(viewModel.currentYear)\(viewModel.currentDayOfWeek)"
                let habits = viewModel.habitDataForDay[documentTitle]?.habitIdArray ?? []
                
                ForEach(habits, id: \.self) { habit in
                    SwipeableRow(
                        content: {
                            HStack {
                                Text(viewModel.habitDataForDay[documentTitle]?.habitIdName[habit] ?? "")
                                    .font(.custom("Big Header", size: 30))
                                    .fontWeight(.black)
                                    .shadow(radius: 3, x: 3, y: 3)
                                    .padding(.vertical, 3)
                                    .overlay(
                                        viewModel.habitDataForDay[documentTitle]?.isHabitStriked[habit] ?? false ?
                                            Rectangle()
                                                .frame(height: 4)
                                                .colorInvert()
                                                .padding(.horizontal, -10)
                                            : nil
                                    )
                                    .onTapGesture {
                                        viewModel.habitStriker(value: habit)
                                    }
                            }
                        },
                        onSwipeLeft: {
                            viewModel.habitRemover(value: habit)
                        },
                        onSwipeRight: {
                            viewModel.habitRemover(value: habit)
                        }
                    )
                }
                
                Spacer()
                
    //            MARK: ADD HABIT Button
                HStack {
                    Button(action: {
                        viewModel.isAddHabitVisible = true
                    }) {
                        Text("Add Habit")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    .padding(20)
                    .sheet(isPresented: $viewModel.isAddHabitVisible) {
                        ZStack {
                            BlurEffect(style: .light)
                            HabitAdder()
                                .presentationDetents([.height(160)])
                        }
                    }
                }
                
                Spacer()
                    .frame(height: 30)
            }
            .foregroundColor(Color.white)
            .padding(.vertical, 10)

    //        MARK: REMOVE HABIT CODE
            .onChange(of: viewModel.selectedHabit) { habitToRemove in
                if let habitToRemove = habitToRemove {
                    viewModel.habitData?.habitIdArray.removeAll { $0 == habitToRemove }
                }
            }
        }
    }
}


struct HabitTracker_Previews: PreviewProvider {
    static var previews: some View {
        return HabitTracker()
            .environmentObject(MockViewModel() as AuthState)
    }
}

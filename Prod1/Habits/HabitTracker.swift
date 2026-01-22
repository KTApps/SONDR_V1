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
    @ObservedObject var authState: AuthState
        
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Button(action: {
                    authState.isBlurViewVisible = false
                }) {
                    BlurEffect(style: .systemMaterialDark)
                }
                VStack {
                    Spacer()
                        .frame(height: geometry.size.height * 0.08)
                    
                    Text("SONDR")
                        .font(AuthState.Typography.font_1_bold)
                    
                    Spacer()
                        .frame(height: geometry.size.height * 0.035)
                    
    //            MARK: WEEKDAY HStack
                    HStack {
                        
    //                MARK: LEFT CHEVRON
                        Button(action: {
                            if authState.weekDayIndexCounter != 0 {
                                authState.weekDayIndexCounter -= 1
                            } else {
                                authState.weekDayIndexCounter += 6
                            }
                            
                            authState.weekdayMinus()
                                                
                        }) {
                            Image(systemName: "chevron.left")
                                .shadow(radius: 3, x: 3, y: 3)
                        }
                        .padding(geometry.size.width * 0.05)
                        
                        Spacer()
                        
    //                MARK: WEEKDAY ARRAY
                        Text(authState.weekDay[authState.weekDayIndexCounter])
                            .font(AuthState.Typography.font_5_bold)
                            .shadow(radius: 3, x: 3, y: 3)
                        
                        Spacer()
                        
    //                MARK: RIGHT CHEVRON
                        Button(action: {
                            if authState.weekDayIndexCounter != 6 {
                                authState.weekDayIndexCounter += 1
                            } else {
                                authState.weekDayIndexCounter = 0
                            }
                            
                            authState.weekdayPlus()
                            
                        }) {
                            Image(systemName: "chevron.right")
                                .shadow(radius: 3, x: 3, y: 3)
                        }
                        .padding(geometry.size.width * 0.05)
                    }
                    .font(AuthState.Typography.font_5_bold)
                    .padding(.horizontal, geometry.size.width * 0.05)
                    .padding(.vertical, -10)
                    
                    /*
                    Text("Day \(authState.habitStreak)")
                        .font(.callout)
                    */
                    Spacer()
                        .frame(height: geometry.size.height * 0.08)
                    
    //            MARK: HABIT ARRAY
                    let documentTitle = "\(authState.currentYear)\(authState.currentDayOfWeek)"
                    let habits = authState.habitDataForDay[documentTitle]?.habitIdArray ?? []
                    
                    ForEach(habits, id: \.self) { habit in
                        SwipeableRow(
                            content: {
                                HStack {
                                    Text(authState.habitDataForDay[documentTitle]?.habitIdName[habit] ?? "")
                                        .font(AuthState.Typography.font_5_bold)
                                        .shadow(radius: 3, x: 3, y: 3)
                                        .padding(.vertical, 3)
                                        .overlay(
                                            authState.habitDataForDay[documentTitle]?.isHabitStriked[habit] ?? false ?
                                                Rectangle()
                                                    .frame(height: geometry.size.height * 0.005)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, -10)
                                                : nil
                                        )
                                        .onTapGesture {
                                            authState.habitStriker(value: habit)
                                        }
                                }
                            },
                            onSwipeLeft: {
                                authState.habitRemover(value: habit)
                            },
                            onSwipeRight: {
                                authState.habitRemover(value: habit)
                            }
                        )
                    }
                    
                    Spacer()
                    
    //            MARK: ADD HABIT Button
                    HStack {
                        Button(action: {
                            authState.isAddHabitVisible = true
                        }) {
                            Text("Add Habit")
                                .font(AuthState.Typography.font_1_bold)
                        }
                        .padding(geometry.size.width * 0.05)
                        .sheet(isPresented: $authState.isAddHabitVisible) {
                            ZStack {
                                BlurEffect(style: .light)
                                HabitAdder(authState: authState)
                                    .presentationDetents([.height(160)])
                            }
                        }
                    }
                    
                    Spacer()
                        .frame(height: geometry.size.height * 0.035)
                }
                .foregroundColor(Color.white)
                .padding(.vertical, geometry.size.height * 0.012)

    //        MARK: REMOVE HABIT CODE
            .onChange(of: authState.selectedHabit) { habitToRemove in
                if let habitToRemove = habitToRemove {
                    authState.habitData?.habitIdArray.removeAll { $0 == habitToRemove }
                }
            }
        }
        }
    }
}


struct HabitTracker_Previews: PreviewProvider {
    static var previews: some View {
        return HabitTracker(authState: AuthState())
    }
}

//
//  CalendarCircle.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 14/09/2024.
//

import SwiftUI
import Charts

struct CalendarCircle: View {
    @ObservedObject var authState: AuthState
    let day: Int
    let selectedMonth: Int
    let selectedYear: Int
    private var dayOfYear: Int {
        return authState.dayOfYear(year: selectedYear, month: selectedMonth, day: day)
    }
    
    // Function to convert the selected day, month, and year to "MM/dd/yyyy" format
    private var formattedDate: String {
        let calendar = Calendar.current
        var components = DateComponents()
        components.day = day
        components.month = selectedMonth
        components.year = selectedYear
        
        if let date = calendar.date(from: components) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM/dd/yyyy"
            return dateFormatter.string(from: date)
        }
        
        return "Invalid Date" // Fallback in case date conversion fails
    }
    
    @Environment(\.presentationMode) var presentationMode
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                authState.darkGray.ignoresSafeArea()
                VStack {
                    Spacer()
                        .frame(height: geometry.size.height * 0.05)
                    
                    HStack {
                        Button {
                            presentationMode.wrappedValue.dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .resizable()
                                .frame(width: geometry.size.width * 0.04, height: geometry.size.width * 0.06)
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                            .frame(width: geometry.size.width * 0.33)
                        
                        Text("SONDR")
                            .font(AuthState.Typography.font_1_bold)
                            .foregroundColor(.white)
                            .shadow(radius: 3, x: 3, y: 3)
                        
                        Spacer()
                    }
                    .padding(.horizontal, geometry.size.width * 0.05)

                    Spacer()
                        .frame(height: geometry.size.height * 0.13)
                    
                    // Display the formatted date above the ZStack
                    Text(formattedDate)
                        .font(AuthState.Typography.font_3_bold)
                        .foregroundColor(.white)
                    
                    ZStack {
                        VStack {
                            Text(authState.selectedCalendarTask ?? "")
                                .font(AuthState.Typography.font_1_bold)
                                .fontWeight(.bold)
                            Text(authState.calendarCircleDailyTime(for: authState.selectedCalendarTask ?? ""))
                                .font(AuthState.Typography.font_3_bold)
                        }
                        .font(.title)
                        let documentTitle = "\(selectedYear)\(dayOfYear)"
                        OuterCalendarCircle(authState: authState, dayOfYear: documentTitle, innerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.33), outerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.39), cornerRadius: 1)
                        InnerCircle(authState: authState, dayOfYear: documentTitle, innerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.22), outerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.28), cornerRadius: 1)
                    }
                    
                    Spacer()
                        .frame(height: geometry.size.height * 0.21)
                }
                .navigationBarBackButtonHidden(true)
                .onAppear {
                    authState.taskTimerDictionarySum(dayOfYear: dayOfYear)
                }
                .onDisappear {
                    authState.selectedCalendarTask = ""
                }
            }
        }
    }
}

#Preview {
    CalendarCircle(authState: AuthState(), day: 1, selectedMonth: 1, selectedYear: 2024)
}

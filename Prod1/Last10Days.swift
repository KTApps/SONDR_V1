//
//  Last10Days.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 05/07/2024.
//

import SwiftUI
import Charts

struct Last10Days: View {
    @ObservedObject var authState: AuthState
    var body: some View {
        GeometryReader { geometry in
            let numberOfColumns = 5
            let numberOfRows = (authState.docTitles.count + numberOfColumns - 1) / numberOfColumns
            
            VStack(alignment: .leading, spacing: geometry.size.width * 0.04) {
                ForEach(0..<numberOfRows, id: \.self) { rowIndex in
                    HStack(spacing: geometry.size.width * 0.04) {
                        ForEach(0..<numberOfColumns, id: \.self) { columnIndex in
                            let index = rowIndex * numberOfColumns + columnIndex
                            if authState.docTitles.count > 0 {
                                withAnimation {
                                    ZStack {
                                        if index < authState.docTitles.count {
                                            let docTitleIndexValue = authState.docTitles[index]
                                            let dayOfYear = Int(docTitleIndexValue.dropFirst(4)) ?? 0
                                            let date = authState.dateFromDayOfYear(index: index, 
                                                                                   year: authState.currentYear,
                                                                                   dayOfYear: dayOfYear)
                                            Text(String(date?.day ?? 0))
                                                .font(.system(size: geometry.size.width * 0.03))
                                                .foregroundColor(.white)
                                            OuterCalendarCircle(authState: authState,
                                                                dayOfYear: docTitleIndexValue,
                                                                innerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.05),
                                                                outerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.07),
                                                                cornerRadius: 1)
                                            Inner10DaysCircle(authState: authState,
                                                              docTitleIndex: index,
                                                              innerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.025),
                                                              outerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.04))
                                        }
                                    }
                                    .frame(width: geometry.size.width / CGFloat(7),
                                           height: geometry.size.width / CGFloat(7))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, geometry.size.width * 0.04)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct Inner10DaysCircle: View {
    @ObservedObject var authState: AuthState
    var docTitleIndex: Int
    var innerRadius: MarkDimension
    var outerRadius: MarkDimension
    
    private func calendarColorReturn(value: String) -> Color {
        if authState.habitDataForDay[authState.docTitles[docTitleIndex]]?.isHabitStriked[value] == true {
            return .blue
        } else {
            return .gray
        }
    }
    
    var body: some View {
        guard docTitleIndex < authState.docTitles.count else {
            return AnyView(Text("Index out of range"))
        }
        
        let docTitleIndexValue = authState.docTitles[docTitleIndex]
        
        Task {
            await authState.listenForCircleData(document: docTitleIndexValue)
        }
        
        // Check if habit data exists and isn’t empty
        if let habits = authState.habitDataForDay[docTitleIndexValue]?.habitIdArray, !habits.isEmpty {
            // Return the Chart view
            return AnyView(
                Chart(habits, id:\.self) { habit in
                    SectorMark(
                        angle: .value("Time Spent", 10),
                        innerRadius: innerRadius,
                        outerRadius: outerRadius,
                        angularInset: 1
                    )
                    .foregroundStyle(calendarColorReturn(value: habit))
                    .cornerRadius(1)
                }
            )
        } else {
            // Return the Chart view
            return AnyView(
                Chart(authState.placeholderTasks, id:\.self) { task in
                    SectorMark(
                        angle: .value("Time Spent", task),
                        innerRadius: innerRadius,
                        outerRadius: outerRadius,
                        angularInset: 1
                    )
                    .foregroundStyle(.gray)
                    .opacity(0.3)
                    .cornerRadius(1)
                }
            )
        }
    }
}

struct Last10Days_Previews: PreviewProvider {
    static var previews: some View {
        return Last10Days(authState: AuthState())
    }
}

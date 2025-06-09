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
        let numberOfColumns = 5
        let numberOfRows = (authState.docTitles.count + numberOfColumns - 1) / numberOfColumns
        
        VStack(alignment: .leading, spacing: 15) {
            ForEach(0..<numberOfRows, id: \.self) { rowIndex in
                HStack(spacing: 15) {
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
                                            .font(.custom("smallNumber", size: 13))
                                            .foregroundColor(.white)
                                        OuterCalendarCircle(authState: authState,
                                                            dayOfYear: docTitleIndexValue,
                                                            innerRadius: 20,
                                                            outerRadius: 27,
                                                            cornerRadius: 5)
                                        Inner10DaysCircle(authState: authState,
                                                          docTitleIndex: index)
                                    }
                                }
                                .frame(width: UIScreen.main.bounds.width / CGFloat(7),
                                       height: UIScreen.main.bounds.width / CGFloat(7))
                            }
                        }
                    }
                }
            }
        }
    }
}

struct Inner10DaysCircle: View {
    @ObservedObject var authState: AuthState
    var docTitleIndex: Int
    
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
                        innerRadius: 11,
                        outerRadius: 17
                    )
                    .foregroundStyle(calendarColorReturn(value: habit))
                    .cornerRadius(5)
                }
            )
        } else {
            // Return the Chart view
            return AnyView(
                Chart(authState.placeholderTasks, id:\.self) { task in
                    SectorMark(
                        angle: .value("Time Spent", task),
                        innerRadius: 11,
                        outerRadius: 17
                    )
                    .foregroundStyle(.gray)
                    .opacity(0.3)
                    .cornerRadius(5)
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

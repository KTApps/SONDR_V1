//
//  Last10Days.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 05/07/2024.
//

import SwiftUI
import Charts

struct Last10Days: View {
    @EnvironmentObject var viewModel: ViewModel
    var body: some View {
        let numberOfColumns = 5
        let numberOfRows = (viewModel.docTitles.count + numberOfColumns - 1) / numberOfColumns
        
        VStack(alignment: .leading, spacing: 15) {
            ForEach(0..<numberOfRows, id: \.self) { rowIndex in
                HStack(spacing: 15) {
                    ForEach(0..<numberOfColumns, id: \.self) { columnIndex in
                        let index = rowIndex * numberOfColumns + columnIndex
                        if viewModel.docTitles.count > 1 {
                            withAnimation {
                                ZStack {
                                    if index < viewModel.docTitles.count {
                                        let dayOfYear = viewModel.docTitles[index] ?? 0
                                        let date = viewModel.dateFromDayOfYear(index: index, year: viewModel.currentYear, dayOfYear: dayOfYear)
                                        Text(String(date?.day ?? 0))
                                            .font(.custom("smallNumber", size: 15))
                                            .foregroundColor(.white)
                                        OuterCircle(innerRadius: 20, outerRadius: 27, cornerRadius: 5)
                                        Inner10DaysCircle(docTitleIndex: index)
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
    @EnvironmentObject var authModel: ViewModel
    var docTitleIndex: Int
    
    private func calendarColorReturn(value: String) -> Color {
        if authModel.habitDataForDay[authModel.docTitles[docTitleIndex] ?? 0]?.isHabitStriked[value] == true {
            return .blue
        } else {
            return .gray
        }
    }
    
    var body: some View {
        guard docTitleIndex < authModel.docTitles.count else {
            return AnyView(Text("Index out of range"))
        }
        
        let docTitle = authModel.docTitles[docTitleIndex]
        
        Task {
            await authModel.listenForHabitData(dayOfYear: docTitle ?? 0)
        }
        
        // Return the Chart view
        return AnyView(
            Chart(authModel.habitDataForDay[docTitle ?? 0]?.habitIdArray ?? [], id:\.self) { habit in
                SectorMark(
                    angle: .value("Time Spent", 10),
                    innerRadius: 11,
                    outerRadius: 18
                )
                .foregroundStyle(calendarColorReturn(value: habit))
                .cornerRadius(5)
            }
        )
    }
}

//struct Last10Days_Previews: PreviewProvider {
//    static var previews: some View {
//        let authModel = AuthViewModel()
//        authModel.currentUser = UserObject(id: "1", username: "NameExample", email: "name@example.com")
//        authModel.docTitles = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] // Example day of year values
//        authModel.habitDataForDay = [
//            1: HabitData(habitIdArray: ["habit1"], habitIdName: ["1" : "1"], isHabitStriked: ["habit1": true]),
//            2: HabitData(habitIdArray: ["habit2"], habitIdName: ["1" : "1"], isHabitStriked: ["habit2": false]),
//            // Add more mock data as needed
//        ]
//        
//        return Last10Days()
//            .environmentObject(authModel)
//    }
//}

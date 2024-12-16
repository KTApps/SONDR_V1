//
//  CalendarCircle.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 14/09/2024.
//

import SwiftUI
import Charts

struct CalendarCircle: View {
    @EnvironmentObject var viewModel: ViewModel
    let day: Int
    let selectedMonth: Int
    let selectedYear: Int
    private var dayOfYear: Int {
        return viewModel.dayOfYear(year: selectedYear, month: selectedMonth, day: day)
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
                viewModel.darkGray.ignoresSafeArea()
                VStack {
                    Spacer()
                        .frame(height: 40)
                    
                    HStack {
                        Button {
                            presentationMode.wrappedValue.dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .resizable()
                                .frame(width: 15, height: 23)
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                            .frame(width: 110)
                        
                        Text("SONDR")
                            .font(.title)
                            .foregroundColor(.white)
                            .shadow(radius: 3, x: 3, y: 3)
                            .fontWeight(.black)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                        .frame(height: 110)
                    
                    // Display the formatted date above the ZStack
                    Text(formattedDate)
                        .font(.title)
                        .foregroundColor(.white)
                    
                    ZStack {
                        VStack {
                            Text("\(viewModel.taskSum)")
                            Text("seconds")
                        }
                        .font(.title)
                        
                        OuterCalendarCircle(dayOfYear: dayOfYear, innerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.29), outerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.4), cornerRadius: 5)
                        InnerCircle(dayOfYear: dayOfYear, innerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.19), outerRadius: MarkDimension(floatLiteral: geometry.size.width * 0.27), cornerRadius: 5)
                    }
                    
                    Spacer()
                        .frame(height: 130)
                }
                .navigationBarBackButtonHidden(true)
                .onAppear {
                    viewModel.taskTimerDictionarySum(dayOfYear: dayOfYear)
                }
            }
        }
    }
}

#Preview {
    CalendarCircle(day: 1, selectedMonth: 1, selectedYear: 2024)
}

import SwiftUI
import Charts

struct CalendarView: View {
    @EnvironmentObject var viewModel: ViewModel
    @State private var selectedDate = Date() // Selected date
    @State private var monthOffset = 0 // Offset to switch between months
    @State private var selectedMonthIndex: Int // e.g. 0 = Jan; 1 = Feb
    @State private var selectedYear: Int
    @State private var isMonthChangerVisible = false
    @State private var selectedMonth = "" // Selected month name
    
    private let months = Calendar.current.monthSymbols // Array of month names
    private let daysOfWeek = Calendar.current.shortWeekdaySymbols // Array of short weekday names
    
    // Initialize with current month and year by default
    init() {
        let currentDate = Date() // defines current date & time
        self._selectedMonthIndex = State(initialValue: Calendar.current.component(.month, from: currentDate) - 1)
        self._selectedYear = State(initialValue: Calendar.current.component(.year, from: currentDate))
        self._selectedMonth = State(initialValue: months[selectedMonthIndex])
    }
    
//    MARK: Returns number of days in a given month
    func daysInMonthForMonthIndex(monthIndex: Int, year: Int) -> Int {
        let calendar = Calendar.current // Calendar object representing current calender system
        var components = DateComponents() // initializes 'DateComponents' object. Allows you to manipulate date components like year, month & day
        components.month = monthIndex + 1 // e.g. Jan = 0 + 1
        components.year = year
        let date = calendar.date(from: components)! // creating a date for the first day of the specified month & year
        let range = calendar.range(of: .day, in: .month, for: date)! // Calculates how many days are in this month
        return range.count // returns the number of days in the month
    }

    func updateSelectedMonthAndYear() {
        let newDateComponents = DateComponents(year: selectedYear, month: selectedMonthIndex + 1)
        if let newDate = Calendar.current.date(from: newDateComponents) {
            selectedDate = newDate
            selectedMonth = months[selectedMonthIndex] // Update selected month
        }
    }

//    MARK: Determines which weekday the 1st day of the month is
    func firstWeekdayOfMonth(for year: Int, month: Int) -> Int {
        let calendar = Calendar.current
        let firstDayOfMonthComponents = DateComponents(year: year, month: month, day: 1) // defines 1st day of month
        if let firstDayOfMonth = calendar.date(from: firstDayOfMonthComponents) { // create date object to represent 1st day of month
            let weekday = calendar.component(.weekday, from: firstDayOfMonth) // checks which day of the week the 1st day is
            return (weekday + 6) % 7 // Adjust to start from Sunday
        }
        return 0
    }
    
    func abbreviatedWeekday(for index: Int) -> String {
        let weekdayIndex = (index + Calendar.current.firstWeekday - 1) % 7
        return daysOfWeek[weekdayIndex]
    }

//  MARK: Calculate the days to display in the calendar grid
    func calculateDaysToDisplay(daysInMonth: Int, firstWeekday: Int) -> [Int?] {
        var daysToDisplay = [Int?]() // create an empty array
        let gridSize = 6 * 7 // 6 rows and 7 columns
        
        // Determine the first day of the month
        let firstDayOfMonth = firstWeekday > 0 ? firstWeekday - 1 : 6
        
        // Creating grid based from days of the month
        for dayIndex in 0..<gridSize {
            if dayIndex < firstDayOfMonth {
                // Display an empty cell for days before the first day of the month
                daysToDisplay.append(nil)
            } else if dayIndex - firstDayOfMonth + 1 <= daysInMonth {
                // Display days from the current month
                daysToDisplay.append(dayIndex - firstDayOfMonth + 1)
            } else {
                // Display nil for days after the current month
                daysToDisplay.append(nil)
            }
        }
        return daysToDisplay
    }
    
    var body: some View {
        let currentMonth = Calendar.current.date(byAdding: .month, value: monthOffset, to: selectedDate)! // calculates new date
        let daysInMonth = daysInMonthForMonthIndex(monthIndex: selectedMonthIndex, year: selectedYear)
        let firstWeekday = firstWeekdayOfMonth(for: selectedYear, month: selectedMonthIndex + 1)
        let daysToDisplay = calculateDaysToDisplay(daysInMonth: daysInMonth,
                                                   firstWeekday: firstWeekday)
        return NavigationView {
            ZStack {
                viewModel.darkGray.ignoresSafeArea()
                VStack {
                    Text("SONDR")
                        .font(.title)
                        .foregroundColor(.white)
                        .shadow(radius: 3, x: 3, y: 3)
                        .fontWeight(.black)

                    Spacer()
                        .frame(height: 20)
                    
                    HStack {
                        Button {
                            isMonthChangerVisible.toggle()
                        } label: {
                            Text(String("\(selectedMonth) \(selectedYear)"))
                                .foregroundColor(.white)
                        }
                        .sheet(isPresented: $isMonthChangerVisible) {
                            VStack {
                                HStack {
                                    Picker(selection: $selectedMonthIndex, label: Text("\(selectedMonth)")) {
                                        ForEach(0..<months.count) { index in
                                            Text(months[index]).tag(index)
                                        }
                                    }
                                    .pickerStyle(WheelPickerStyle())
                                    .onChange(of: selectedMonthIndex) { newValue in
                                        selectedMonth = months[newValue]
                                    }
                                    
                                    Picker(selection: $selectedYear, label: Text(String("\(selectedYear)"))) {
                                        ForEach(selectedYear - 10..<selectedYear + 10, id: \.self) { year in
                                            Text(String("\(year)"))
                                                .tag(year)
                                        }
                                    }
                                    .pickerStyle(WheelPickerStyle())
                                }
                                
                                Spacer()
                                    .frame(height: 10)
                                
                                Button {
                                    isMonthChangerVisible.toggle()
                                } label: {
                                    Text("Submit")
                                        .font(.title)
                                }
                            }
                            .presentationDetents([.medium])
                        }
                        
                        Spacer()
                        
                        Button {
                            monthOffset -= 1
                            selectedMonthIndex -= 1
                            if selectedMonthIndex < 0 {
                                selectedMonthIndex = months.count - 1
                                selectedYear -= 1
                            }
                            updateSelectedMonthAndYear()
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.white)
                        }

                        Button {
                            monthOffset += 1
                            selectedMonthIndex += 1
                            if selectedMonthIndex >= months.count {
                                selectedMonthIndex = 0
                                selectedYear += 1
                            }
                            updateSelectedMonthAndYear()
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal)
                    
                    ScrollView {
                        VStack {
                            // Display weekday labels row
                            HStack(spacing: 0) {
                                ForEach(0..<7) { column in
                                    Text(abbreviatedWeekday(for: column))
                                        .frame(width: UIScreen.main.bounds.width / CGFloat(7), height: UIScreen.main.bounds.width / CGFloat(7))
                                }
                            }
                            .foregroundColor(.gray)
                            
                            // Display days in the calendar
                            ForEach(0..<((daysInMonth + firstWeekday - 1) / 7) + 1) { row in // Calculates the number of rows needed to display all the days of the month
                                HStack(spacing: 0) {
                                    ForEach(0..<7) { column in
                                        if let day = daysToDisplay[row * 7 + column] {
                                            NavigationLink {
                                                CalendarCircle(day: day, selectedMonth: selectedMonthIndex + 1, selectedYear: selectedYear)
                                            } label: {
                                                // Display a CalendarDayCell if day exists
                                                CalendarDayCell(day: day, selectedMonth: selectedMonthIndex + 1, selectedYear: selectedYear)
                                                    .frame(width: UIScreen.main.bounds.width / CGFloat(7),
                                                           height: UIScreen.main.bounds.width / CGFloat(7))
                                            }
                                        } else {
                                            // Display an empty view when day is doesnt exist
                                            Color.clear
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 30)
            }
            .onAppear {
                // Update selectedDate when the view appears
                let newDateComponents = DateComponents(year: selectedYear,
                                                       month: selectedMonthIndex + 1)
                if let newDate = Calendar.current.date(from: newDateComponents) {
                    selectedDate = newDate
                }
            }
        }
    }
}

struct CalendarDayCell: View {
    @EnvironmentObject var viewModel: ViewModel
    let day: Int
    let selectedMonth: Int
    let selectedYear: Int
    private var dayOfYear: Int {
        return viewModel.dayOfYear(year: selectedYear, month: selectedMonth, day: day)
    }
    
    var body: some View {
        let dayOfYearString = "\(selectedYear)\(dayOfYear)"
        ZStack {
            Text("\(day)") // Display the day number
                .font(.system(size: 12))
                .foregroundColor(.white)
            OuterCalendarCircle(dayOfYear: dayOfYearString, innerRadius: 18, outerRadius: 24, cornerRadius: 3)
            InnerCircle(dayOfYear: dayOfYearString, innerRadius: 10, outerRadius: 15, cornerRadius: 3)
        }
        .onAppear {
            Task {
                await viewModel.listenForCircleData(document: dayOfYearString)
            }
        }
    }
}

struct InnerCircle: View {
    @EnvironmentObject var viewModel: ViewModel
    let dayOfYear: String
    let innerRadius: MarkDimension
    let outerRadius: MarkDimension
    let cornerRadius: CGFloat
    private func calendarColorReturn(value: String) -> Color {
        if viewModel.habitDataForDay[dayOfYear]?.isHabitStriked[value] == true {
            return .blue
        } else {
            return .gray
        }
    }
    
    var body: some View {
        if let habits = viewModel.habitDataForDay[dayOfYear]?.habitIdArray, !habits.isEmpty {
            Chart(habits, id:\.self) { habit in
                SectorMark(
                    angle: .value("Time Spent", 10),
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    angularInset: 1
                )
                .foregroundStyle(calendarColorReturn(value: habit))
                .cornerRadius(cornerRadius)
            }
            .onAppear {
                Task {
                    await viewModel.listenForCircleData(document: dayOfYear)
                }
            }
        } else {
            Chart(viewModel.placeholderTasks, id: \.self) { task in
                SectorMark(
                    angle: .value("Time Spent", task),
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    angularInset: 1
                )
                .foregroundStyle(.gray)
                .opacity(0.3)
                .cornerRadius(cornerRadius)
            }
        }
    }
}

struct OuterCalendarCircle: View {
    @EnvironmentObject var viewModel: ViewModel
    let dayOfYear: String
    let innerRadius: MarkDimension
    let outerRadius: MarkDimension
    let cornerRadius: CGFloat
    
    @State private var pieSelection: Double?
    @State private var animatedOpacity: Double = 1.0
    
    var body: some View {
        if let tasks = viewModel.taskDataForDay[dayOfYear]?.tasks, !tasks.isEmpty {
            let timeSpent = viewModel.taskDataForDay[dayOfYear]?.taskTimerDictionary ?? [:]
            Chart(tasks, id: \.self) { task in
                if let taskTime = timeSpent[task] {
                    SectorMark(
                        angle: .value("Time Spent", taskTime),
                        innerRadius: innerRadius,
                        outerRadius: outerRadius,
                        angularInset: 1
                    )
                    .cornerRadius(cornerRadius)
                    .opacity(viewModel.selectedCalendarTask == nil || viewModel.selectedCalendarTask == task ? 1 : animatedOpacity)
                }
            }
            .chartAngleSelection(value: $pieSelection)
            .onChange(of: pieSelection, initial: false) { _ , newValue in
                withAnimation(.easeInOut(duration: 0.5)) {
                    if let newValue {
                        viewModel.selectedCalendarTask = viewModel.taskForTime(newValue, tasks: tasks, timeSpent: timeSpent)
                    }
                    animatedOpacity = 0.3
                }
            }
        } else {
            Chart(viewModel.placeholderTasks, id: \.self) { task in
                SectorMark(
                    angle: .value("Time Spent", task),
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    angularInset: 1
                )
                .foregroundStyle(.gray)
                .opacity(0.3)
                .cornerRadius(cornerRadius)
            }
        }
    }
}

extension Date {
    func startOfMonth() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components)!
    }
}

struct CalendarView_Previews: PreviewProvider {
    static var previews: some View {
        return CalendarView()
            .environmentObject(MockViewModel() as ViewModel)
    }
}

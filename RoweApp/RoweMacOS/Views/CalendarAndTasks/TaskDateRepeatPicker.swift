import SwiftUI
import RoweCore

struct TaskDateRepeatPicker: View {
    @Binding var selectedDate: Date?
    @Binding var repeatRule: RepeatRule?
    @Binding var reminderDate: Date?
    var onDismiss: () -> Void

    @State private var displayedMonth: Date = Date()
    @State private var dateSearchText: String = ""
    @State private var showRepeatOptions: Bool = false

    private let calendar = Calendar.current
    private let weekdayHeaders = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("Date", text: $dateSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        applyNaturalLanguageDate(dateSearchText)
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider().opacity(0.3)

            // Month navigation header
            HStack {
                Text(monthTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Button {
                    HapticsManager.shared.tap()
                    displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                Button {
                    HapticsManager.shared.tap()
                    let today = calendar.startOfDay(for: Date())
                    displayedMonth = today
                    selectedDate = today
                } label: {
                    Image(systemName: "record.circle")
                        .font(.system(size: 12))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Today")

                Button {
                    HapticsManager.shared.tap()
                    displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)

            // Weekday grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                ForEach(weekdayHeaders, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                ForEach(monthGridDates(), id: \.self) { date in
                    let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                    let isCurrentMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
                    let isPast = date < calendar.startOfDay(for: Date())

                    Button {
                        HapticsManager.shared.tap()
                        selectedDate = calendar.startOfDay(for: date)
                    } label: {
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : (isCurrentMonth && !isPast ? .primary : .secondary))
                            .frame(width: 28, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? Color(hex: "#3E3F47") : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            Button {
                HapticsManager.shared.tap()
                selectedDate = nil
            } label: {
                Text("Clear Date")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            Divider().opacity(0.3)

            // Remind Me
            HStack {
                Image(systemName: "alarm")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Text(reminderDate == nil ? "Remind Me..." : "Reminder set")
                    .font(.system(size: 12.5))
                    .foregroundStyle(reminderDate == nil ? .secondary : .primary)
                Spacer()
                Button {
                    HapticsManager.shared.toggle()
                    if reminderDate == nil {
                        reminderDate = calendar.date(byAdding: .hour, value: 1, to: Date())
                    } else {
                        reminderDate = nil
                    }
                } label: {
                    Image(systemName: reminderDate == nil ? "plus" : "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)

            // Repeat Rule
            HStack {
                Image(systemName: "repeat")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary)
                RoweGlassMenuPicker(
                    items: [Optional<RepeatFrequency>.none] + RepeatFrequency.allCases.map { Optional($0) },
                    selection: Binding(
                        get: { repeatRule?.frequency },
                        set: { freq in
                            if let freq {
                                let base = selectedDate ?? Date()
                                let wd = calendar.component(.weekday, from: base)
                                repeatRule = RepeatRule(frequency: freq, weekdayIndex: wd, startDate: base)
                            } else {
                                repeatRule = nil
                            }
                        }
                    ),
                    titleForItem: { $0?.rawValue ?? "None" }
                )

                Spacer()

                if repeatRule != nil {
                    Button {
                        HapticsManager.shared.tap()
                        repeatRule = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 8)
        .frame(width: 244)
        .onAppear {
            if let selectedDate {
                displayedMonth = selectedDate
            }
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: displayedMonth)
    }

    private func monthGridDates() -> [Date] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: monthStart) // 1 = Sun
        let offset = weekday - 1
        guard let gridStart = calendar.date(byAdding: .day, value: -offset, to: monthStart) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func applyNaturalLanguageDate(_ raw: String) {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let today = calendar.startOfDay(for: Date())
        if lower == "today" {
            selectedDate = today
        } else if lower == "tomorrow" {
            selectedDate = calendar.date(byAdding: .day, value: 1, to: today)
        } else if lower == "next week" {
            selectedDate = calendar.date(byAdding: .day, value: 7, to: today)
        }
        if let selectedDate {
            displayedMonth = selectedDate
        }
    }
}

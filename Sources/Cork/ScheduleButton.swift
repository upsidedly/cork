import SwiftUI
import CorkCore

struct ScheduleButton: View {
    @Bindable var model: CorkController
    @State private var open = false
    private var schedule: RandomizationSchedule { model.board.desktop.randomizationSchedule ?? RandomizationSchedule() }
    var body: some View {
        Button(schedule.enabled ? schedule.frequency.title : "Schedule", systemImage: "clock") { open = true }
            .labelStyle(.iconOnly).accessibilityLabel("Randomization schedule: \(schedule.frequency.title)")
            .help("Choose when Cork rolls a new collage")
            .popover(isPresented: $open, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Randomize automatically").font(.headline)
                    Picker("Frequency", selection: binding(\.frequency)) {
                        ForEach(RandomizationFrequency.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if schedule.frequency == .custom {
                        HStack {
                            Stepper("Every \(schedule.every)", value: binding(\.every), in: 1...schedule.unit.maximum)
                            Picker("Unit", selection: binding(\.unit)) { ForEach(ScheduleUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
                        }
                    }
                    if [.day, .week, .morningEvening].contains(schedule.frequency) {
                        timePicker(schedule.frequency == .morningEvening ? "Morning" : "Time", evening: false)
                    }
                    if schedule.frequency == .morningEvening { timePicker("Evening", evening: true) }
                    if schedule.frequency == .week {
                        Picker("Day", selection: binding(\.weekday)) {
                            ForEach(1...7, id: \.self) { index in Text(Calendar.current.weekdaySymbols[index - 1]).tag(index) }
                        }
                    }
                    if let due = schedule.nextRun, schedule.enabled {
                        Text("Next: \(due.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                    if let problem = model.scheduleDriver.problem { Text(problem).font(.caption).foregroundStyle(.secondary) }
                    Text("Uses your current colours or mood. Notes and kept images stay put. Missed times after sleep run once, without a burst of rolls.").font(.caption).foregroundStyle(.secondary)
                }.padding(16).frame(width: 350)
            }
    }
    private func binding<Value>(_ path: WritableKeyPath<RandomizationSchedule, Value>) -> Binding<Value> {
        Binding(get: { schedule[keyPath: path] }, set: { value in
            var next = schedule; next[keyPath: path] = value; next.every = min(next.every, next.unit.maximum)
            model.run { try await model.setSchedule(next) }
        })
    }
    private func timePicker(_ title: String, evening: Bool) -> some View {
        DatePicker(title, selection: Binding(get: {
            Calendar.current.date(bySettingHour: evening ? schedule.eveningHour : schedule.hour,
                minute: evening ? schedule.eveningMinute : schedule.minute, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            var next = schedule
            if evening { next.eveningHour = parts.hour ?? 18; next.eveningMinute = parts.minute ?? 0 }
            else { next.hour = parts.hour ?? 8; next.minute = parts.minute ?? 0 }
            model.run { try await model.setSchedule(next) }
        }), displayedComponents: .hourAndMinute)
    }
}

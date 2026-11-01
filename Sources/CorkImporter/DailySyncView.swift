import SwiftUI

struct DailySyncView: View {
    @Bindable var model: ImporterModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Daily Pinterest Sync").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { model.showsDailySync = false }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            if model.account != nil && !model.selected.isEmpty && model.step == .boards {
                Text("Keep \(model.selected.count) selected boards fresh").font(.headline)
                Text("Start from today. The latest 100 pins per board form a baseline; older pins aren't backfilled. New images get measured colours and join the rotation pool. Your current collage stays put.")
                    .font(.callout).foregroundStyle(.secondary)
                DatePicker("Check at", selection: $model.dailyTime, displayedComponents: .hourAndMinute)
                Picker("New images per day", selection: $model.dailySettings.maximumPerDay) {
                    ForEach([5, 10, 20], id: \.self) { Text("Up to \($0)").tag($0) }
                }
                Toggle("Allow daily Pinterest-cookie access to this profile until I pause or disconnect", isOn: $model.dailyConsent)
                Text("Only Pinterest receives your cookies. No cookies or browser keys are saved. Cork Importer remembers read-only profile-folder permission; you can disconnect to remove this daily connection.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Enable Daily Sync for Selected Boards") { model.enableDaily() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.dailyConsent || model.selected.count > 50 || model.busy)
            } else if model.dailySettings.profile != nil {
                Text(model.dailySettings.enabled ? "On · Every day at \(model.dailyTime.formatted(date: .omitted, time: .shortened))" : "Paused").font(.headline)
                Text("\(model.dailySettings.boards.count) boards · up to \(model.dailySettings.maximumPerDay) new images a day")
                Text(model.dailyStatus).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                if let date = model.dailyState.lastAttempt {
                    LabeledContent("Last checked") { Text(date, format: .dateTime.month(.abbreviated).day().hour().minute()) }
                }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.dailySettings.boards) { board in Text(board.name).font(.callout) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button(model.dailySettings.enabled ? "Pause Daily Sync" : "Resume Daily Sync") { model.setDailyEnabled(!model.dailySettings.enabled) }
                    Button("Check Now") { model.checkDaily() }.disabled(!model.dailySettings.enabled)
                    Spacer()
                }.disabled(model.busy)
                HStack {
                    Button("Choose Boards…") { model.chooseDailyBoards() }
                    Spacer()
                    Button("Remove Connection", role: .destructive) { model.forgetDaily() }
                }.disabled(model.busy)
            } else {
                Text("Connect Pinterest, select your boards, then choose Keep Selected Boards Fresh Daily.")
                    .foregroundStyle(.secondary)
                Button("Connect and Choose Boards…") { model.chooseDailyBoards() }.buttonStyle(.borderedProminent)
            }
            Divider()
            Text("No app rebuild is needed for new pins. Each check rereads only this profile's Pinterest cookies. If access expires, the check stops without showing password prompts in the background.")
                .font(.callout).foregroundStyle(.secondary)
            Text("At most 32 MB downloaded per day; syncing pauses below 2 GB free. Original downloads and staging aren't archived. Removed pins stay excluded. Checks missed during sleep coalesce after wake.")
                .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 440)
        }.padding(24).frame(width: 540).task { await model.reloadDaily() }
    }
}

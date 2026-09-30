import SwiftData
import SwiftUI

/// 자주 가는 곳 한 곳: 이름("회사"), 도착 시각, 역에서 걷는 시간, 반복 요일.
/// 새로 등록할 때와 고칠 때 같은 화면을 쓴다.
struct PlaceEditor: View {
    enum Target {
        case new(Station)
        case edit(Place)
    }

    let target: Target
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var stationName = ""
    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var walk = 0
    @State private var days = 0
    @State private var showSearch = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("이름 (예: 회사, 학교)", text: $name)
                    .font(.body.weight(.semibold))
                Button {
                    showSearch = true
                } label: {
                    HStack {
                        Text("도착역").foregroundStyle(Theme.ink)
                        Spacer()
                        if let s = StationDirectory.shared.station(named: stationName) { LineDots(lines: s.lines) }
                        Text(stationName).foregroundStyle(Theme.mute)
                    }
                }
            }

            Section {
                Toggle("도착 시각 정하기", isOn: $hasTime.animation())
                    .disabled(days != 0)
                if hasTime {
                    DatePicker("몇 시까지", selection: $time, displayedComponents: .hourAndMinute)
                }
                Stepper(value: $walk, in: 0...40) {
                    HStack {
                        Text("역에서 걸어서")
                        Spacer()
                        Text(walk == 0 ? "없음" : "\(walk)분").foregroundStyle(Theme.mute)
                    }
                }
            } footer: {
                Text("시각을 정해 두면 칩을 누를 때 바로 채워져요.")
            }

            Section {
                HStack(spacing: 6) {
                    ForEach(Place.weekdayOrder, id: \.self) { day in
                        let on = days & 1 << day != 0
                        Button {
                            withAnimation {
                                days ^= 1 << day
                                if days != 0 { hasTime = true }
                            }
                        } label: {
                            Text(Place.weekdayNames[day])
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(on ? Theme.now : Color(.secondarySystemFill), in: Circle())
                                .foregroundStyle(on ? .white : Theme.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    preset("평일", (2...6).reduce(0) { $0 | 1 << $1 })
                    preset("매일", (1...7).reduce(0) { $0 | 1 << $1 })
                    preset("안 함", 0)
                }
            } header: {
                Text("반복")
            } footer: {
                Text(days == 0
                     ? "요일을 고르면 그날마다 앱을 열지 않아도 나갈 시각에 알려줘요."
                     : "\(Place.daysText(days) ?? "") \(Fmt.time.string(from: time))까지 도착하도록, 그날 나갈 시각에 알려줘요. 하루만 빼려면 홈에서 '오늘은 안 가요'를 누르세요.")
            }

            if case .edit(let place) = target {
                Section {
                    Button("이곳 지우기", role: .destructive) {
                        context.delete(place)
                        try? context.save()
                        refreshRoutines()
                        onDone()
                    }
                }
            }
        }
        .navigationTitle(isNew ? "자주 가는 곳 등록" : "자주 가는 곳")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || stationName.isEmpty)
            }
        }
        .sheet(isPresented: $showSearch) {
            StationSearchSheet { station in
                // 이름이 역 이름 그대로였으면 새 역 이름으로 따라 바꾼다
                if name == stationName { name = station.name }
                stationName = station.name
                showSearch = false
            }
        }
        .onAppear(perform: load)
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private func preset(_ title: String, _ value: Int) -> some View {
        Button(title) {
            withAnimation {
                days = value
                if value != 0 { hasTime = true }
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(days == value ? Theme.now : Theme.mute)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch target {
        case .new(let station):
            name = station.name
            stationName = station.name
        case .edit(let p):
            name = p.name
            stationName = p.stationName
            walk = p.walkFromStation
            days = p.repeatDays
            hasTime = p.deadlineMinutes >= 0
            if let d = p.deadline(on: .now) { time = d }
        }
    }

    private func save() {
        let cal = Calendar.current
        let minutes = hasTime ? cal.component(.hour, from: time) * 60 + cal.component(.minute, from: time) : -1
        let place: Place
        switch target {
        case .new:
            place = Place(name: name, stationName: stationName, walkFromStation: walk, deadlineMinutes: minutes)
            context.insert(place)
        case .edit(let p):
            place = p
            // 이름을 바꾸면 진행 중인 이동도 새 이름으로 (반복 일정과 짝이 맞게)
            let trips = (try? context.fetch(FetchDescriptor<PlannedTrip>())) ?? []
            for t in trips where !t.cancelled && Routines.isSame(t, p) { t.placeName = name.trimmingCharacters(in: .whitespaces) }
        }
        place.name = name.trimmingCharacters(in: .whitespaces)
        place.stationName = stationName
        place.walkFromStation = walk
        place.deadlineMinutes = minutes
        place.repeatDays = hasTime ? days : 0
        place.favorite = true
        try? context.save()
        refreshRoutines()
        onDone()
    }

    private func refreshRoutines() {
        let context = context
        Task { await Routines.refresh(context: context, force: true) }
    }
}

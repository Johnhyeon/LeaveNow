import SwiftData
import SwiftUI

/// 자주 가는 곳(직접 등록)과 최근 간 곳 칩. 누르면 그곳으로 바로 채운다.
/// 길게 누르면 자주 가는 곳에 넣거나 빼고, 지울 수 있다.
struct PlaceShortcuts: View {
    var selectedStation: String? = nil
    var showsTime = false
    let onPick: (Place) -> Void

    @Query(sort: \Place.lastUsedAt, order: .reverse) private var places: [Place]
    @Environment(\.modelContext) private var context
    @State private var showSearch = false

    private var favorites: [Place] { places.filter(\.favorite) }
    private var recents: [Place] { Array(places.filter { !$0.favorite }.prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("자주 가는 곳") {
                ForEach(favorites) { p in chip(p, symbol: "star.fill") }
                Button {
                    showSearch = true
                } label: {
                    Label("등록", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(Theme.mute.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .foregroundStyle(Theme.mute)
                }
                .buttonStyle(.plain)
            }
            if !recents.isEmpty {
                row("최근") {
                    ForEach(recents) { p in chip(p, symbol: nil) }
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            StationSearchSheet { station in
                register(station)
                showSearch = false
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(Theme.mute)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content() }.padding(.vertical, 2)
            }
        }
    }

    private func chip(_ p: Place, symbol: String?) -> some View {
        let selected = selectedStation == p.stationName
        let title = showsTime ? [p.name, p.deadlineText].compactMap { $0 }.joined(separator: " · ") : p.name
        return Button {
            onPick(p)
        } label: {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.caption2).foregroundStyle(.orange) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? Theme.now.opacity(0.14) : Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(selected ? Theme.now : Theme.ink)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(p.favorite ? "자주 가는 곳에서 빼기" : "자주 가는 곳에 넣기",
                   systemImage: p.favorite ? "star.slash" : "star") {
                p.favorite.toggle()
                try? context.save()
            }
            Button("지우기", systemImage: "trash", role: .destructive) {
                context.delete(p)
                try? context.save()
            }
        }
    }

    /// 역을 자주 가는 곳으로 등록. 이미 있으면 별만 붙인다
    private func register(_ station: Station) {
        if let existing = places.first(where: { $0.stationName == station.name }) {
            existing.favorite = true
        } else {
            let p = Place(name: station.name, stationName: station.name, walkFromStation: 0, deadlineMinutes: -1)
            p.favorite = true
            context.insert(p)
        }
        try? context.save()
    }
}

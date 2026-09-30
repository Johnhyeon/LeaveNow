import SwiftData
import SwiftUI

/// 자주 가는 곳(직접 등록)과 최근 간 곳 칩. 누르면 그곳으로 바로 채운다.
/// 길게 누르면 편집(이름·시각·반복), 자주 가는 곳에 넣거나 빼기, 지우기.
struct PlaceShortcuts: View {
    var selectedStation: String? = nil
    var showsTime = false
    let onPick: (Place) -> Void

    @Query(sort: \Place.lastUsedAt, order: .reverse) private var places: [Place]
    @Environment(\.modelContext) private var context
    @State private var showSearch = false
    @State private var picked: Station?
    @State private var editing: EditTarget?

    private struct EditTarget: Identifiable {
        let id = UUID()
        let target: PlaceEditor.Target
    }

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
        .sheet(isPresented: $showSearch, onDismiss: {
            // 역을 고르면 이어서 이름·시각·반복을 정한다
            if let station = picked {
                picked = nil
                if let existing = places.first(where: { $0.stationName == station.name && $0.favorite }) {
                    editing = EditTarget(target: .edit(existing))
                } else {
                    editing = EditTarget(target: .new(station))
                }
            }
        }) {
            StationSearchSheet { station in
                picked = station
                showSearch = false
            }
        }
        .sheet(item: $editing) { item in
            NavigationStack {
                PlaceEditor(target: item.target) { editing = nil }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { editing = nil } } }
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
        let title = showsTime ? p.chipText : p.name
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
            Button("편집", systemImage: "pencil") { editing = EditTarget(target: .edit(p)) }
            Button(p.favorite ? "자주 가는 곳에서 빼기" : "자주 가는 곳에 넣기",
                   systemImage: p.favorite ? "star.slash" : "star") {
                p.favorite.toggle()
                try? context.save()
            }
            Button("지우기", systemImage: "trash", role: .destructive) {
                context.delete(p)
                try? context.save()
                let context = context
                Task { await Routines.refresh(context: context, force: true) }
            }
        }
    }
}

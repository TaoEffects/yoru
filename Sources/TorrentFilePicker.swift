import SwiftUI

struct TorrentFilePicker: View {
    @Environment(\.yoruTheme) private var theme
    @Environment(\.yoruLabels) private var labels
    let files: [TorrentFile]
    @Binding var selection: Set<Int>
    var locked: Bool

    @State private var rowFrames: [Int: CGRect] = [:]
    @State private var sweep: Sweep?
    @Namespace private var viewport
    private let scrollClock = Timer.publish(every: 0.10, on: .main, in: .common).autoconnect()

    private struct Sweep {
        let first: Int
        let initial: Set<Int>
        let selecting: Bool
        var pointer: CGPoint
    }

    private struct RowFrames: PreferenceKey {
        static let defaultValue: [Int: CGRect] = [:]
        static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
            value.merge(nextValue()) { _, latest in latest }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(files) { file in
                            row(file)
                                .background {
                                    GeometryReader { row in
                                        Color.clear.preference(key: RowFrames.self, value: [file.id: row.frame(in: .named(viewport))])
                                    }
                                }
                                .id(file.id)
                        }
                    }
                    .padding(2)
                }
                .coordinateSpace(name: viewport)
                .onPreferenceChange(RowFrames.self) { rowFrames = $0 }
                .simultaneousGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named(viewport))
                    .onChanged { movement in
                        guard !locked else { return }
                        if sweep == nil, let first = file(at: movement.startLocation.y) {
                            sweep = Sweep(first: first, initial: selection,
                                          selecting: !selection.contains(first), pointer: movement.location)
                        }
                        guard let current = sweep else { return }
                        sweep?.pointer = movement.location
                        let y = min(max(movement.location.y, 1), geometry.size.height - 1)
                        if let last = file(at: y) { extend(current, through: last) }
                    }
                    .onEnded { _ in sweep = nil })
                .onReceive(scrollClock) { _ in scrollEdges(geometry.size.height, proxy: proxy) }
            }
        }
    }

    private func row(_ file: TorrentFile) -> some View {
        let selected = selection.contains(file.id)
        let filename = URL(fileURLWithPath: file.path).deletingPathExtension().lastPathComponent
        return HStack(spacing: 11) {
            Image(systemName: selected ? "checkmark.circle.fill" : file.isVideo ? "film" : "doc")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(selected ? theme.accent : theme.mutedText)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if file.isVideo, let episode = file.episode {
                    Text(labels("Épisode \(episode)")).font(YoruTypography.display(20))
                }
                Text(filename)
                    .font(YoruTypography.text(15)).lineLimit(2)
                    .foregroundStyle(file.episode == nil ? theme.primary : theme.mutedText)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.mutedText)
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
        .frame(minHeight: 49)
        .background(selected ? theme.tint : theme.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? theme.accent.opacity(0.36) : theme.divider)
            .allowsHitTesting(false))
        .contentShape(Rectangle())
        .onTapGesture { toggle(file.id) }
        .directionalTarget(radius: 9) { toggle(file.id) }
        .disabled(locked)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(selected ? "Sélectionné" : "Non sélectionné")
        .accessibilityAction { toggle(file.id) }
        .help(file.path)
    }

    private func toggle(_ id: Int) {
        guard !locked, sweep == nil else { return }
        if selection.contains(id) { selection.remove(id) }
        else { selection.insert(id) }
    }

    private func file(at y: CGFloat) -> Int? {
        rowFrames.first { y >= $0.value.minY && y <= $0.value.maxY }?.key
            ?? rowFrames.min { abs($0.value.midY - y) < abs($1.value.midY - y) }?.key
    }

    private func extend(_ current: Sweep, through last: Int) {
        guard let start = files.firstIndex(where: { $0.id == current.first }),
              let end = files.firstIndex(where: { $0.id == last }) else { return }
        let range = files[min(start, end)...max(start, end)].map(\.id)
        selection = current.selecting ? current.initial.union(range) : current.initial.subtracting(range)
    }

    private func scrollEdges(_ height: CGFloat, proxy: ScrollViewProxy) {
        guard !locked, let current = sweep, height > 66 else { return }
        let up = current.pointer.y < 27
        let down = current.pointer.y > height - 27
        guard up || down else { return }
        let visible = files.indices.filter { index in
            guard let rect = rowFrames[files[index].id] else { return false }
            return rect.maxY > 0 && rect.minY < height
        }
        guard let edge = up ? visible.first : visible.last else { return }
        let target = edge + (up ? -1 : 1)
        guard files.indices.contains(target) else { return }
        let id = files[target].id
        extend(current, through: id)
        proxy.scrollTo(id, anchor: up ? .top : .bottom)
    }
}

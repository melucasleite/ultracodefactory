import CodeFactoryKit
import SwiftUI

struct BoardView: View {
    @Environment(FactoryModel.self) private var model
    let project: String
    var search: String
    var kindFilter: String?
    @Binding var openCard: Card?

    private func matches(_ card: Card) -> Bool {
        if let kindFilter, card.kind != kindFilter { return false }
        guard !search.isEmpty else { return true }
        return card.title.localizedCaseInsensitiveContains(search)
            || card.file.localizedCaseInsensitiveContains(search)
            || (card.cardID?.localizedCaseInsensitiveContains(search) ?? false)
    }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 12
            let columns = CGFloat(CardStatus.allCases.count)
            let width = max(230, (geo.size.width - 32 - spacing * (columns - 1)) / columns)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(CardStatus.allCases) { status in
                        ColumnView(
                            status: status,
                            cards: model.cards.filter { $0.status == status && matches($0) },
                            fabricating: status == .todo ? model.fabricating(in: project) : [],
                            openCard: $openCard
                        )
                        .frame(width: width)
                    }
                }
                .padding(16)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            .scrollIndicators(.automatic)
        }
        .background(BoardBackground())
    }
}

/// A faint blueprint grid behind the board.
private struct BoardBackground: View {
    var body: some View {
        Canvas { gc, size in
            let step: CGFloat = 24
            var path = Path()
            var x: CGFloat = 0
            while x < size.width { path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y < size.height { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)); y += step }
            gc.stroke(path, with: .color(.primary.opacity(0.035)), lineWidth: 1)
        }
        .background(.background)
        .ignoresSafeArea()
    }
}

struct ColumnView: View {
    @Environment(FactoryModel.self) private var model
    let status: CardStatus
    let cards: [Card]
    let fabricating: [Job]
    @Binding var openCard: Card?
    @State private var targeted = false

    var body: some View {
        let tint = Theme.color(for: status)
        VStack(spacing: 0) {
            Rectangle().fill(tint.gradient).frame(height: 3)
            HStack(spacing: 8) {
                Image(systemName: status.symbol).foregroundStyle(tint).font(.callout.weight(.semibold))
                Text(status.title).font(.headline)
                Spacer()
                Text("\(cards.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(fabricating) { job in
                        FabricatingTile(job: job)
                    }
                    ForEach(cards) { card in
                        CardTile(card: card, openCard: $openCard)
                    }
                    if cards.isEmpty && fabricating.isEmpty {
                        Text(targeted ? "Drop to move here" : "Empty")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(targeted ? tint : Color.primary.opacity(0.08), lineWidth: targeted ? 2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: targeted ? tint.opacity(0.35) : .clear, radius: 10)
        .animation(.snappy(duration: 0.18), value: targeted)
        .dropDestination(for: CardReference.self) { refs, _ in
            for ref in refs { model.move(ref, to: status) }
            return !refs.isEmpty
        } isTargeted: { targeted = $0 }
    }
}

struct CardTile: View {
    @Environment(FactoryModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let card: Card
    @Binding var openCard: Card?
    @State private var hovering = false
    @State private var confirmTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.callout.weight(.medium))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if let id = card.cardID {
                    Text("#\(id)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                if let kind = card.kind { KindChip(kind: kind) }
                if let priority = card.priority {
                    Label(priority, systemImage: "flag.fill")
                        .font(.caption2).foregroundStyle(.orange).labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
                if let updated = card.updated {
                    Text(updated).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(hovering ? 0.18 : 0.06), radius: hovering ? 6 : 2, y: hovering ? 3 : 1)
        }
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9)
                .fill(Theme.color(for: card.status))
                .frame(width: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(hovering ? 0.15 : 0.07))
        }
        .scaleEffect(hovering ? 1.01 : 1)
        .animation(.snappy(duration: 0.15), value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onHover { hovering = $0 }
        .onTapGesture { openCard = card }
        .draggable(CardReference(card)) {
            Text(card.title)
                .font(.callout.weight(.medium))
                .padding(10)
                .frame(width: 220, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        }
        .contextMenu {
            Button("Open", systemImage: "doc.text") { openCard = card }
            Menu("Move To") {
                ForEach(CardStatus.allCases.filter { $0 != card.status }) { status in
                    Button(status.title, systemImage: status.symbol) { model.move(CardReference(card), to: status) }
                }
            }
            Divider()
            Button("Run Work on This Card", systemImage: "play.fill") {
                Task {
                    if let job = await model.launch(.work, project: card.project, text: card.file) {
                        openWindow(id: "console", value: job.id)
                    }
                }
            }
            Divider()
            Button("Reveal in Finder", systemImage: "folder") { Finder.reveal(model.cardURL(card)) }
            Button("Open in Default Editor", systemImage: "square.and.pencil") { Finder.open(model.cardURL(card)) }
            Button("Copy Path", systemImage: "doc.on.doc") { Finder.copy(model.cardURL(card)?.path ?? "") }
            Divider()
            Button("Move to Trash…", systemImage: "trash", role: .destructive) { confirmTrash = true }
        }
        .confirmationDialog("Move “\(card.title)” to the Trash?", isPresented: $confirmTrash) {
            Button("Move to Trash", role: .destructive) { model.trash(card) }
        } message: {
            Text("You can restore it from the Trash in Finder.")
        }
    }
}

struct KindChip: View {
    let kind: String

    var body: some View {
        let color = Theme.color(forKind: kind)
        Text(kind)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.35)))
            .foregroundStyle(color)
    }
}

/// A card that an agent is still writing.
struct FabricatingTile: View {
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.2.fill")
                    .symbolEffect(.rotate, options: .repeat(.continuous))
                    .foregroundStyle(Theme.safetyOrange)
                Text("Fabricating…").font(.caption.weight(.semibold)).foregroundStyle(Theme.safetyOrange)
            }
            Text(job.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .padding(.top, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .top) {
            HazardStripes().frame(height: 5).opacity(0.85)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hazardYellow.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

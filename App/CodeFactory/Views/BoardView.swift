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
                            fabricating: model.fabricating(in: project, status: status),
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
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: status.symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.6), radius: 6)
                Text(status.title).font(.headline)
                Spacer()
                Text("\(cards.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .glassCapsule(tint: tint)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassPanel(cornerRadius: 14, tint: tint)
            .overlay(alignment: .top) {
                Capsule().fill(tint.gradient).frame(height: 2.5).padding(.horizontal, 18).shadow(color: tint, radius: 6)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(fabricating) { job in
                        FabricatingTile(job: job)
                    }
                    ForEach(cards) { card in
                        CardTile(card: card, openCard: $openCard)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.6, anchor: .top).combined(with: .opacity).combined(with: .offset(y: -30)),
                                removal: .opacity.combined(with: .scale(scale: 0.9))
                            ))
                    }
                    if cards.isEmpty && fabricating.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: targeted ? "arrow.down.circle" : status.symbol)
                                .font(.title2)
                            Text(targeted ? "Drop to move here" : "Nothing here")
                                .font(.caption)
                        }
                        .foregroundStyle(targeted ? tint : Color.secondary.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 90)
                    }
                }
                .padding(4)
                .glassGroup(spacing: 10)
            }
            .scrollIndicators(.never)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(targeted ? tint.opacity(0.12) : Color.primary.opacity(0.025))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(targeted ? tint.opacity(0.9) : Color.primary.opacity(0.06),
                              style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [6, 4] : []))
        }
        .shadow(color: targeted ? tint.opacity(0.45) : .clear, radius: 18)
        .animation(.spring(duration: 0.3, bounce: 0.3), value: targeted)
        .animation(.spring(duration: 0.55, bounce: 0.4), value: cards.map(\.id))
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

    private var fresh: Bool { model.freshCards.contains(card.id) }

    var body: some View {
        let tint = Theme.color(for: card.status)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                    .shadow(color: tint, radius: 4)
                    .padding(.top, 6)
                Text(card.title)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                if let kind = card.kind { KindChip(kind: kind) }
                if let priority = card.priority {
                    Label(priority, systemImage: "flag.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.orange).labelStyle(.titleAndIcon)
                }
                if let id = card.cardID {
                    Text("#\(id)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let pr = card.pullRequest, let number = card.pullRequestNumber {
                    Button {
                        Finder.open(pr)
                    } label: {
                        Label("Review PR #\(number)", systemImage: "arrow.triangle.pull")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(.green)
                            .glassCapsule(tint: .green, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .help(pr.absoluteString)
                }
                if let updated = card.updated {
                    Text(updated).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: 14, interactive: true)
        .overlay {
            if fresh {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.safetyOrange.gradient, lineWidth: 1.5)
                    .shadow(color: Theme.safetyOrange, radius: 10)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.safetyOrange)
                            .symbolEffect(.bounce, options: .repeat(2))
                            .padding(6)
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.8), value: fresh)
        .shadow(color: .black.opacity(hovering ? 0.25 : 0.1), radius: hovering ? 14 : 5, y: hovering ? 8 : 2)
        .scaleEffect(hovering ? 1.025 : 1)
        .animation(.spring(duration: 0.3, bounce: 0.35), value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { hovering = $0 }
        .onTapGesture { openCard = card }
        .draggable(CardReference(card)) {
            Text(card.title)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .padding(12)
                .frame(width: 230, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5))
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
                Text("Fabricating…")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.safetyOrange)
                Spacer()
                ProgressView().controlSize(.mini)
            }
            Text(job.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .padding(.top, 4)
        .overlay(alignment: .top) {
            HazardStripes().frame(height: 4).opacity(0.9)
        }
        .glassPanel(cornerRadius: 14, tint: Theme.safetyOrange)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Theme.safetyOrange.opacity(0.35), radius: 12)
    }
}

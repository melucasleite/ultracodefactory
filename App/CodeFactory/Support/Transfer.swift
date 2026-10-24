import AppKit
import CodeFactoryKit
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    static let cardReference = UTType(exportedAs: "app.codefactory.card-reference")
}

extension CardReference: @retroactive Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .cardReference)
    }
}

enum Finder {
    static func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Asks for a folder; returns nil if the panel is cancelled.
    @MainActor
    static func chooseFolder(message: String, startingAt path: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = message
        panel.prompt = "Choose"
        if let path, !path.isEmpty { panel.directoryURL = URL(filePath: (path as NSString).expandingTildeInPath) }
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func chooseExecutable(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.directoryURL = URL(filePath: "/opt/homebrew/bin")
        return panel.runModal() == .OK ? panel.url : nil
    }
}

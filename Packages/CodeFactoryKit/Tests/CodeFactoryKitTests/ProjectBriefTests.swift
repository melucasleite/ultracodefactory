import Foundation
import Testing
@testable import CodeFactoryKit

@Suite struct ProjectBriefTests {
    @Test func markdownCarriesEveryAnswer() {
        let brief = ProjectBrief(
            name: "Plant Pal",
            summary: "Reminds you to water your plants.",
            platforms: ["iOS", "Web app"],
            stack: ["SwiftUI", "Next.js"],
            features: ["Accounts & sign-in", "Push notifications"],
            designStyle: "Playful",
            appearance: "Light and dark",
            accentHex: "#2FBF71",
            notes: "Keep it cute."
        )
        let md = brief.markdown
        #expect(md.hasPrefix("# Plant Pal\n"))
        for needle in ["- iOS", "- SwiftUI", "- Push notifications", "Style: Playful", "#2FBF71", "Keep it cute."] {
            #expect(md.contains(needle))
        }
    }

    @Test func emptyStackDelegatesTheChoice() {
        #expect(ProjectBrief(name: "X").markdown.contains("Not chosen yet"))
    }

    @Test func plannerPromptTargetsTheProposedFolder() {
        let prompt = BacklogPlanner.prompt(cardsFolder: URL(filePath: "/tmp/app/.codefactory"), fromExistingCode: false)
        #expect(prompt.contains("/tmp/app/.codefactory/proposed"))
        #expect(prompt.contains("PROJECT.md"))
        #expect(prompt.contains("status: proposed"))
    }

    @Test func scaffoldCreatesARepoAndRefusesNonEmptyFolders() async throws {
        let parent = FileManager.default.temporaryDirectory.appending(path: "cf-scaffold-\(UUID().uuidString)")
        let project = try await ProjectScaffold.create(in: parent, brief: ProjectBrief(name: "Plant Pal"))
        #expect(project.repository.lastPathComponent == "plant-pal")
        #expect(FileManager.default.fileExists(atPath: project.repository.appending(path: "PROJECT.md").path))
        #expect(FileManager.default.fileExists(atPath: project.cardsRoot.appending(path: "proposed").path))
        #expect(FileManager.default.fileExists(atPath: project.repository.appending(path: ".git").path))

        await #expect(throws: ScaffoldError.self) {
            try await ProjectScaffold.create(in: parent, brief: ProjectBrief(name: "Plant Pal"))
        }
    }
}

@Suite struct BriefSuggesterTests {
    let platforms = ["Web app", "iOS"]
    let styles = ["Minimal", "Playful"]
    let looks = ["Dark first"]

    @Test func parsesAReplyWrappedInProse() throws {
        let reply = """
        Sure! Here you go:
        {"platforms": ["iOS", "Smartwatch"], "stack": ["SwiftUI", "  CloudKit  "], "features": ["Water reminders", "Plant journal"], "designStyle": "Playful", "appearance": "Neon"}
        """
        let s = try #require(BriefSuggester.parse(reply, platforms: platforms, styles: styles, appearances: looks))
        #expect(s.platforms == ["iOS"])            // unknown platform dropped
        #expect(s.stack == ["SwiftUI", "CloudKit"]) // trimmed
        #expect(s.designStyle == "Playful")
        #expect(s.appearance == nil)               // not an allowed value
    }

    @Test func garbageIsNil() {
        #expect(BriefSuggester.parse("no json here", platforms: platforms, styles: styles, appearances: looks) == nil)
    }

    @Test func promptListsTheAllowedValues() {
        let p = BriefSuggester.prompt(name: "X", summary: "Y", platforms: platforms, styles: styles, appearances: looks)
        #expect(p.contains("\"Web app\", \"iOS\""))
        #expect(p.contains("ONLY a JSON object"))
    }
}

import Foundation
import Testing
@testable import CodeFactoryKit

@Suite struct FrontmatterTests {
    let sample = """
    ---
    title: "Ship the conveyor belt"
    status: todo
    kind: feature
    # a comment that must survive
    updated: 2026-01-01
    ---

    Body text.
    """

    @Test func parsesFlatFields() {
        let fm = Frontmatter.parse(sample)
        #expect(fm.present)
        #expect(fm.fields["title"] == "Ship the conveyor belt")
        #expect(fm.fields["kind"] == "feature")
        #expect(fm.body.trimmingCharacters(in: .whitespacesAndNewlines) == "Body text.")
    }

    @Test func documentWithoutFrontmatter() {
        let fm = Frontmatter.parse("# Just markdown\n")
        #expect(!fm.present)
        #expect(fm.fields.isEmpty)
        #expect(Frontmatter.updating("# Just markdown\n", with: ["status": "done"]) == "# Just markdown\n")
    }

    @Test func updatesInPlaceAndPreservesOtherLines() {
        let out = Frontmatter.updating(sample, with: ["status": "done", "updated": "2026-10-23", "owner": "bot"])
        #expect(out.contains("status: done\n"))
        #expect(out.contains("updated: 2026-10-23\n"))
        #expect(out.contains("# a comment that must survive"))
        #expect(out.contains("owner: bot\n---"))
        #expect(out.hasSuffix("Body text."))
        #expect(!out.contains("status: todo"))
    }
}

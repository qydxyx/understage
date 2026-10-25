import XCTest
@testable import Understage

final class IdeasTests: XCTestCase {
    func testVideoSuggestionsInclude1080p() {
        let item = SelectedItem(
            url: URL(fileURLWithPath: "/tmp/clip.mp4"),
            name: "clip.mp4",
            isDirectory: false
        )
        let ideas = Ideas.suggestions(selected: [item], folder: URL(fileURLWithPath: "/tmp"))
        XCTAssertTrue(ideas.contains { $0.query == "1080p" })
        XCTAssertTrue(ideas.contains { $0.query == "extract audio" })
    }

    func testFavoritesAppear() {
        let ideas = Ideas.suggestions(
            selected: [],
            folder: URL(fileURLWithPath: "/tmp"),
            favorites: [Favorite(query: "organize by type")]
        )
        XCTAssertTrue(ideas.contains { $0.query == "organize by type" })
    }
}

final class RuleMatchTests: XCTestCase {
    func testTriggerAndFolder() {
        let rule = Rule(
            trigger: "web",
            instruction: "export 1000px wide",
            folderPrefix: "/Users/me/site"
        )
        XCTAssertTrue(rule.matches(query: "for the web", folder: URL(fileURLWithPath: "/Users/me/site/img")))
        XCTAssertFalse(rule.matches(query: "for the web", folder: URL(fileURLWithPath: "/tmp")))
        XCTAssertFalse(rule.matches(query: "jpg", folder: URL(fileURLWithPath: "/Users/me/site")))
    }

    func testPromptBlock() {
        let rules = [
            Rule(trigger: "*", instruction: "never overwrite"),
            Rule(trigger: "jpg", instruction: "quality 80"),
        ]
        let block = RuleStore.promptBlock(
            rules: rules,
            query: "jpg",
            folder: nil
        )
        XCTAssertTrue(block.contains("never overwrite"))
        XCTAssertTrue(block.contains("quality 80"))
    }
}

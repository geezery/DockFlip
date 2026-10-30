import Testing
@testable import DockFlipKit

@Suite("TabTitle")
struct TabTitleTests {
    @Test func splitsSiteSuffix() {
        let gmail = TabTitle.split("Inbox (3) - antti@example.com - Gmail")
        #expect(gmail.page == "Inbox (3) - antti@example.com")
        #expect(gmail.site == "Gmail")
        let teams = TabTitle.split("Chat | Microsoft Teams")
        #expect(teams.site == "Microsoft Teams")
    }

    @Test func keepsTitlesWithoutSite() {
        #expect(TabTitle.split("New Tab").site == nil)
        let long = TabTitle.split("Q3 plan - draft for the board meeting next week")
        #expect(long.site == nil)
        #expect(long.page == "Q3 plan - draft for the board meeting next week")
    }
}

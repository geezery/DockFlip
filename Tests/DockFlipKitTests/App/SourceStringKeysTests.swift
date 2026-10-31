import Testing

/// The scanner `LocalizableStringsTests.everyKeyInSourcesIsInEnglish` relies on:
/// each shape of key the code uses is found, and what is not a key is not.
@Suite("SourceStringKeys")
struct SourceStringKeysTests {
    @Test func readsAppKitAndSwiftUIKeys() throws {
        let source = """
        item.title = L("Settings…")
        Text("Clean Up").font(.title)
        Button("Remove") { remove() }
        Toggle("Launch at login", isOn: $on)
        Label("No picture", systemImage: "lock")
        Section("Unused windows") { rows }
        .help(Text("Suggest this app again"))
        Text(on ? LocalizedStringKey("On") : LocalizedStringKey("Off"))
        """
        let keys = try SourceStringKeys.keys(in: source, labels: [])
        #expect(keys.sorted() == [
            "Clean Up", "Launch at login", "No picture", "Off", "On", "Remove",
            "Settings…", "Suggest this app again", "Unused windows"
        ])
    }

    @Test func skipsWhatIsNotAKey() throws {
        let source = #"""
        // Text("Only in a comment")
        Text(verbatim: name)
        Text("")
        Text("\(count) windows")
        Text(title)
        CustomText("Not one of SwiftUI's")
        image.accessibilityDescription = "Not a call"
        menu.addItem(ClosureMenuItem(String(format: L("%ld tabs"), n)))
        """#
        let keys = try SourceStringKeys.keys(in: source, labels: [])
        #expect(keys == ["%ld tabs"])
    }

    @Test func readsLabelledKeysOfLocalizedStringKeyProperties() throws {
        let declaration = """
        struct StepHeader: View {
            let symbol: String
            let title: LocalizedStringKey
            let subtitle: LocalizedStringKey
            private var hint: LocalizedStringKey {
        """
        let labels = try SourceStringKeys.keyProperties(in: declaration)
        #expect(labels == ["title", "subtitle"])
        let use = """
        StepHeader(symbol: "lock", title: "Allow Accessibility",
                   subtitle: "DockFlip needs one permission.")
        """
        let keys = try SourceStringKeys.keys(in: use, labels: labels)
        #expect(keys.sorted() == ["Allow Accessibility", "DockFlip needs one permission."])
    }

    @Test func readsComputedAndAssignedKeys() throws {
        let source = """
        private var primaryTitle: LocalizedStringKey {
            switch step {
            case .welcome: return "Get Started"
            default: return "Continue"
            }
        }
        let fallback: LocalizedStringKey = "Untitled"
        var other: String { "Not a key" }
        """
        let keys = try SourceStringKeys.keys(in: source, labels: [])
        #expect(keys.sorted() == ["Continue", "Get Started", "Untitled"])
    }

    @Test func unescapesQuotes() throws {
        let keys = try SourceStringKeys.keys(in: #"Text("Say \"hi\"")"#, labels: [])
        #expect(keys == [#"Say "hi""#])
    }

    @Test func missingLeavesOutTheExceptions() {
        let used: [String] = ["Back", "⌘Tab", "Gone", "Gone"]
        let missing = SourceStringKeys.missing(used, from: ["Back"])
        #expect(missing == ["Gone"])
    }
}

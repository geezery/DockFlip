import SwiftUI

// Browser tabs under their window in the Dock list: a branch line per tab, the
// selected tab marked in the app's colour, a colour chip per site, duplicates
// marked, long lists folded behind "Show all N tabs".

/// "15 tabs · Gmail, YouTube, Teams +3": how many tabs, and the sites most of them are on.
enum TabSummary {
    static func text(for tabs: [BrowserTab]) -> String {
        var counts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        for (index, tab) in tabs.enumerated() {
            guard let site = tab.site else { continue }
            counts[site, default: 0] += 1
            if firstSeen[site] == nil { firstSeen[site] = index }
        }
        let sites = counts.keys.sorted {
            counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : firstSeen[$0]! < firstSeen[$1]!
        }
        var text = String(format: L("%ld tabs"), tabs.count)
        if !sites.isEmpty {
            text += " · " + sites.prefix(3).joined(separator: ", ")
            if sites.count > 3 { text += " +\(sites.count - 3)" }
        }
        return text
    }
}

/// A stable colour per site, so the same site always wears the same chip.
enum SiteColor {
    static func hue(for site: String) -> Double {
        var hash: UInt32 = 2_166_136_261
        for byte in site.lowercased().utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Double(hash % 360) / 360
    }
}

/// The tabs of one browser window, hanging under it like branches.
struct TabListView: View {
    let row: WindowListRow
    let tabs: [BrowserTab]
    let hidden: Int
    @ObservedObject var model: WindowListModel
    let popup: WindowListPopup

    var body: some View {
        let titles = Dictionary(grouping: row.tabs, by: \.fullTitle).filter { $0.value.count > 1 }
        VStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { position, tab in
                // A later copy of a tab already open in this window.
                let isDuplicate = titles[tab.fullTitle].map { $0.first?.id != tab.id } ?? false
                TabRowView(
                    tab: tab,
                    isLast: position == tabs.count - 1 && hidden == 0,
                    isDuplicate: isDuplicate,
                    tint: row.tint,
                    model: model,
                    popup: popup
                )
            }
            if hidden > 0 {
                Button {
                    popup.toggleExpanded(row.id)
                } label: {
                    HStack(spacing: 8) {
                        TreeBranch(isLast: true)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                            .frame(width: 14)
                        Text(String(format: L("Show all %ld tabs"), row.tabs.count))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                    .padding(.leading, 30)
                    .frame(height: WindowListLayout.tabRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, WindowListLayout.tabListPadding)
    }
}

struct TabRowView: View {
    let tab: BrowserTab
    let isLast: Bool
    let isDuplicate: Bool
    let tint: Color
    @ObservedObject var model: WindowListModel
    let popup: WindowListPopup

    private var hovering: Bool { model.hoveredTab == tab.id }

    var body: some View {
        HStack(spacing: 8) {
            TreeBranch(isLast: isLast)
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                .frame(width: 14)
            Circle()
                .fill(tab.isSelected ? tint : Color.clear)
                .overlay(Circle().strokeBorder(Color.primary.opacity(tab.isSelected ? 0 : 0.25), lineWidth: 1))
                .frame(width: 6, height: 6)
            Text(verbatim: tab.title)
                .font(.system(size: 12, weight: tab.isSelected ? .semibold : .regular))
                .foregroundStyle(tab.isSelected ? Color.primary : Color.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if isDuplicate {
                Text("Duplicate")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 0.75))
            }
            if let site = tab.site {
                SiteChip(site: site)
            }
        }
        .padding(.leading, 30)
        .padding(.trailing, 10)
        .frame(height: WindowListLayout.tabRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(hovering ? 0.12 : 0))
                .padding(.leading, 48)
        )
        .contentShape(Rectangle())
        .onHover { model.setHoveredTab(tab.id, window: tab.windowID, $0) }
        .onTapGesture { popup.pickTab(tab) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(tab.isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// The site a tab is on, in its own colour.
struct SiteChip: View {
    let site: String

    var body: some View {
        let hue = SiteColor.hue(for: site)
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hue: hue, saturation: 0.7, brightness: 0.85))
                .frame(width: 5, height: 5)
            Text(verbatim: site)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color(hue: hue, saturation: 0.55, brightness: 0.9).opacity(0.18), in: Capsule())
        .fixedSize()
    }
}

/// The branch line in front of a tab: down from the window, then right to the tab.
struct TreeBranch: Shape {
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + 3.5
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: isLast ? rect.midY - 4 : rect.maxY))
        if isLast {
            path.addQuadCurve(to: CGPoint(x: x + 4, y: rect.midY), control: CGPoint(x: x, y: rect.midY))
        } else {
            path.move(to: CGPoint(x: x, y: rect.midY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}


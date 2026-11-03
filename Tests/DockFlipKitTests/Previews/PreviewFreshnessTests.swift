import CoreGraphics
import Testing
@testable import DockFlipKit

/// A window is pictured again only when it may look different.
@Suite("Thumbnails: when a picture is out of date")
struct PreviewFreshnessTests {
    typealias Freshness = PreviewFreshness<Int>
    let page = Freshness.Signature(title: "Budget.xlsx", size: CGSize(width: 1200, height: 800))

    @Test func aWindowWithoutAPictureNeedsOne() {
        let freshness = Freshness()
        #expect(freshness.needsPicture(1, now: page, isActive: false))
    }

    @Test func aWindowLeftInTheBackgroundKeepsItsPicture() {
        var freshness = Freshness()
        freshness.pictured(1, as: page, usesAtStart: freshness.usesNow(1))
        #expect(!freshness.needsPicture(1, now: page, isActive: false))
        // Moving it changes nothing in its picture; only its size counts.
        let moved = Freshness.Signature(title: "Budget.xlsx", size: CGSize(width: 1200.2, height: 799.8))
        #expect(!freshness.needsPicture(1, now: moved, isActive: false))
    }

    @Test func theActiveWindowIsPicturedAgain() {
        var freshness = Freshness()
        freshness.pictured(1, as: page, usesAtStart: 0)
        #expect(freshness.needsPicture(1, now: page, isActive: true))
    }

    @Test func aWindowWorkedInSinceItsPictureIsPicturedAgain() {
        var freshness = Freshness()
        freshness.pictured(1, as: page, usesAtStart: freshness.usesNow(1))
        freshness.used(1)
        #expect(freshness.needsPicture(1, now: page, isActive: false))
        // A new picture after that is up to date again.
        freshness.pictured(1, as: page, usesAtStart: freshness.usesNow(1))
        #expect(!freshness.needsPicture(1, now: page, isActive: false))
    }

    @Test func workDuringTheCaptureLeavesThePictureOutOfDate() {
        var freshness = Freshness()
        let atStart = freshness.usesNow(1)
        freshness.used(1)
        freshness.pictured(1, as: page, usesAtStart: atStart)
        #expect(freshness.needsPicture(1, now: page, isActive: false))
    }

    @Test func aNewTitleOrSizeNeedsANewPicture() {
        var freshness = Freshness()
        freshness.pictured(1, as: page, usesAtStart: 0)
        #expect(freshness.needsPicture(1, now: .init(title: "Forecast.xlsx", size: CGSize(width: 1200, height: 800)), isActive: false))
        #expect(freshness.needsPicture(1, now: .init(title: "Budget.xlsx", size: CGSize(width: 900, height: 800)), isActive: false))
    }

    @Test func forgottenWindowsNeedAPictureAgain() {
        var freshness = Freshness()
        freshness.pictured(1, as: page, usesAtStart: 0)
        freshness.pictured(2, as: page, usesAtStart: 0)
        freshness.keepOnly([2])
        #expect(freshness.needsPicture(1, now: page, isActive: false))
        #expect(!freshness.needsPicture(2, now: page, isActive: false))
        freshness.forgetAll()
        #expect(freshness.needsPicture(2, now: page, isActive: false))
    }
}

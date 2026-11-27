import XCTest
@testable import OpenFuseCore
@testable import OpenFuseData

/// Covers the pure decisions extracted from the 2026-11-27 bug list: which page
/// the player returns to, whether the loading route still has content, and how a
/// remote failure is classified for the UI.
final class PlayerRoutePolicyTests: XCTestCase {
    /// Stand-in for `AppRoute`; the policy is deliberately route-type agnostic.
    private enum Route: Equatable {
        case home
        case library
        case browser
        case loading
        case player
    }

    private func remembered(current: Route, existing: Route?) -> Route? {
        PlayerReturnRoutePolicy.route(current: current, existing: existing, isPlaceholder: { $0 == .loading })
    }

    /// The reported bug: resuming from the home page pushed `.loading`, the
    /// player then stored `.loading` as the return route, and closing it landed
    /// back on the spinner.
    func testLoadingIsNeverRecordedAsTheReturnRoute() {
        XCTAssertEqual(remembered(current: .loading, existing: nil), nil)
    }

    /// `resume()` remembers the page before it enters `.loading`, and
    /// `startPlayer()` must not overwrite that with the placeholder.
    func testExistingRouteSurvivesTheLoadingPlaceholder() {
        XCTAssertEqual(remembered(current: .loading, existing: .home), .home)
        XCTAssertEqual(remembered(current: .loading, existing: .library), .library)
        XCTAssertEqual(remembered(current: .loading, existing: .browser), .browser)
    }

    /// A real page always wins: the user navigated somewhere new.
    func testRealPageReplacesTheRememberedRoute() {
        XCTAssertEqual(remembered(current: .home, existing: .library), .home)
        XCTAssertEqual(remembered(current: .browser, existing: .home), .browser)
        XCTAssertEqual(remembered(current: .library, existing: nil), .library)
    }

    /// `startPlayer()` is skipped entirely while another item is playing, so the
    /// policy is only consulted for a fresh session.
    func testFirstPlaybackFromHomeRemembersHome() {
        XCTAssertEqual(remembered(current: .home, existing: nil), .home)
    }

    /// The root view fallback: a `.loading` route with nothing in flight and no
    /// error is stale and must show the home page.
    func testStaleLoadingRouteShowsTheHomePage() {
        XCTAssertFalse(PlaybackLoadingState.showsLoadingPage(isLoading: false, error: nil))
        XCTAssertFalse(PlaybackLoadingState.showsLoadingPage(isLoading: false, error: ""))
        XCTAssertFalse(PlaybackLoadingState.showsLoadingPage(isLoading: false, error: "   "))
    }

    func testActiveOrFailedLoadingRouteStillShowsTheLoadingPage() {
        XCTAssertTrue(PlaybackLoadingState.showsLoadingPage(isLoading: true, error: nil))
        XCTAssertTrue(PlaybackLoadingState.showsLoadingPage(isLoading: true, error: "下载失败"))
        XCTAssertTrue(PlaybackLoadingState.showsLoadingPage(isLoading: false, error: "这个视频所在的来源已被移除"))
    }

    /// The retry/cancel paths rely on `resume()` clearing the error and setting
    /// the flag again, so a retry after a failure keeps showing the page.
    func testRetryAfterFailureShowsTheLoadingPage() {
        XCTAssertTrue(PlaybackLoadingState.showsLoadingPage(isLoading: true, error: nil))
    }

    // MARK: - Remote failure classification

    func testMissingCredentialOffersThePasswordForm() {
        let error = WebDAVError.missingCredential(sourceName: "Fixture")
        XCTAssertEqual(RemoteDirectoryRecovery.action(for: error), .enterPassword)
    }

    func testOtherRemoteFailuresKeepThePlainRetry() {
        XCTAssertEqual(RemoteDirectoryRecovery.action(for: WebDAVError.unauthorized), .retry)
        XCTAssertEqual(RemoteDirectoryRecovery.action(for: WebDAVError.notFound), .retry)
        XCTAssertEqual(RemoteDirectoryRecovery.action(for: WebDAVError.httpStatus(500)), .retry)
        XCTAssertEqual(RemoteDirectoryRecovery.action(for: WebDAVError.network("timeout")), .retry)
        XCTAssertEqual(RemoteDirectoryRecovery.action(for: URLError(.timedOut)), .retry)
    }

    /// The wording must name the source: «用户名或密码不正确» sent users to re-add
    /// the whole source instead of typing the password again.
    func testMissingCredentialWordingNamesTheSource() {
        let error = WebDAVError.missingCredential(sourceName: "OpenList")
        XCTAssertEqual(error.errorDescription, "需要输入 OpenList 的密码")
        XCTAssertEqual(error.missingCredentialSourceName, "OpenList")
        XCTAssertEqual(WebDAVError.missingCredential(sourceName: "").errorDescription, "需要输入密码")
        XCTAssertNil(WebDAVError.unauthorized.missingCredentialSourceName)
    }

    // MARK: - Notice affordance

    func testOnlyKeychainNoticeOffersTheRetryButton() {
        XCTAssertTrue(StatusNoticeKind.keychainAuthorization.offersCredentialRetry)
        XCTAssertFalse(StatusNoticeKind.info.offersCredentialRetry)
    }

    // MARK: - Remote history records

    func testEveryRemoteKindIsRecognised() {
        for kind in ["webdav", "jellyfin", "emby", "smb", "plex"] {
            XCTAssertTrue(PlaybackSourceKind.isRemote(kind), kind)
        }
        XCTAssertTrue(PlaybackSourceKind.isRemote("WebDAV"))
    }

    func testLocalAndUnknownKindsAreNotRemote() {
        XCTAssertFalse(PlaybackSourceKind.isRemote(nil))
        XCTAssertFalse(PlaybackSourceKind.isRemote(""))
        XCTAssertFalse(PlaybackSourceKind.isRemote("local"))
        XCTAssertFalse(PlaybackSourceKind.isRemote("file"))
    }

    /// `PlaybackRecord.isRemote` only knows the two kinds the home rail can fetch
    /// a still for; the resume path must not inherit that narrower set.
    func testResumeRecognisesKindsTheHomeRailDoesNot() {
        let smb = PlaybackRecord(mediaPath: "/srv/movie.mkv", sourceKind: "smb", sourceID: "s1")
        XCTAssertFalse(smb.isRemote)
        XCTAssertTrue(PlaybackSourceKind.isRemote(smb.sourceKind))
    }

    func testSourceRemovedOffersRemoveFromHistory() {
        XCTAssertTrue(LoadingFailureKind.sourceRemoved.offersRemoveFromHistory)
        XCTAssertFalse(LoadingFailureKind.generic.offersRemoveFromHistory)
    }

    // MARK: - Add outcome

    func testAddOutcomeReportsTheKeychainWarning() {
        let warning = SourceAddOutcome(source: "source", warning: "来源已保存到本次会话，但 Keychain 写入失败：denied")
        XCTAssertTrue(warning.hasWarning)
        XCTAssertEqual(warning.source, "source")

        let clean = SourceAddOutcome(source: "source")
        XCTAssertFalse(clean.hasWarning)
        XCTAssertFalse(SourceAddOutcome(source: "source", warning: "  ").hasWarning)
    }

    /// The source form's three outcomes: close, show the failure in place, or stay
    /// open with a warning the user has to acknowledge.
    func testSourceFormClosesOnlyWhenNothingNeedsSaying() {
        XCTAssertEqual(
            SourceFormStep.step(for: SourceAddOutcome(source: "source"), statusMessage: "已添加"),
            .close
        )
    }

    func testSourceFormShowsTheFailureInPlace() {
        XCTAssertEqual(
            SourceFormStep.step(for: Optional<SourceAddOutcome<String>>.none, statusMessage: "用户名或密码不正确"),
            .showError("用户名或密码不正确")
        )
        XCTAssertEqual(SourceFormStep.step(for: Optional<SourceAddOutcome<String>>.none, statusMessage: nil), .showError("连接失败"))
        XCTAssertEqual(SourceFormStep.step(for: Optional<SourceAddOutcome<String>>.none, statusMessage: ""), .showError("连接失败"))
    }

    /// The Keychain warning must keep the form open; dismissing on success is
    /// exactly what hid it before.
    func testSourceFormStaysOpenForAKeychainWarning() {
        let outcome = SourceAddOutcome(
            source: "source",
            warning: "来源已保存到本次会话，但 Keychain 写入失败：denied"
        )
        XCTAssertEqual(
            SourceFormStep.step(for: outcome, statusMessage: "已添加"),
            .showWarning("来源已保存到本次会话，但 Keychain 写入失败：denied")
        )
    }
}

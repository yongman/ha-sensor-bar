import XCTest
@testable import HASensorBarApp

final class PopoverPresenterTests: XCTestCase {
    @MainActor
    func testRetriesUntilTheAnchorAndPopoverAreVisible() async {
        let presenter = PopoverPresenter()
        let shown = expectation(description: "Popover shown after anchor layout and a silent show failure")
        var attempts = 0
        presenter.show(retryDelay: 1_000_000) {
            attempts += 1
            if attempts < 3 { return false }
            shown.fulfill()
            return true
        }
        await fulfillment(of: [shown], timeout: 2)
        XCTAssertEqual(attempts, 3)
        presenter.cancel()
    }

    @MainActor
    func testClosingCancelsPendingPresentation() async {
        let presenter = PopoverPresenter()
        let began = expectation(description: "Waiting for a visible anchor")
        let reopened = expectation(description: "A closed popover must not reopen")
        reopened.isInverted = true
        var attempts = 0
        presenter.show(retryDelay: 50_000_000) {
            attempts += 1
            if attempts == 1 { began.fulfill() }
            else { reopened.fulfill() }
            return false
        }
        await fulfillment(of: [began], timeout: 2)
        presenter.cancel()
        await fulfillment(of: [reopened], timeout: 0.15)
        XCTAssertEqual(attempts, 1)
    }

    @MainActor
    func testUnavailableAnchorHasABoundedRetryBudget() async {
        let presenter = PopoverPresenter()
        let exhausted = expectation(description: "Retry budget exhausted")
        var attempts = 0
        presenter.show(attempts: 3, retryDelay: 1_000_000) {
            attempts += 1
            if attempts == 3 { exhausted.fulfill() }
            return false
        }
        await fulfillment(of: [exhausted], timeout: 2)
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(attempts, 3)
        presenter.cancel()
    }
}

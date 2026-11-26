import Foundation

enum TransitionKey { case to }
final class UIViewController { var navigationController: UINavigationController? }
final class UINavigationController {}
final class UIViewControllerTransitionCoordinator {
  var destination: UIViewController?
  func viewController(forKey: TransitionKey) -> UIViewController? { destination }
}
final class ListNavigationSelectionTarget {}

private final class Harness {
  var isLegacyIOS = true
  var clearsNavigationSelectionOnViewWillAppear = true
  var navigationSelectionViewController: UIViewController?
  var navigationSelectionTransitionIdentifier: ObjectIdentifier?
  weak var legacyNavigationSelectionTransitionCoordinator: UIViewControllerTransitionCoordinator?
  var navigationSelectionTransitionSession: Int?
  var navigationSelectionTransitionTarget: ListNavigationSelectionTarget?
  var skipsNextNavigationSelectionFinalization = false
  var liveSession: Int? = 1
  var liveTarget: ListNavigationSelectionTarget? = ListNavigationSelectionTarget()
  var navigationSelectionSessionForTransition: (() -> Int?)? { { self.liveSession } }
  var selectedNavigationTarget: (() -> ListNavigationSelectionTarget?)? { { self.liveTarget } }
  func findContentViewController() -> UIViewController? { navigationSelectionViewController }
  func isNavigationDestination(
    _ viewController: UIViewController,
    _ destination: UIViewController,
    in navigationController: UINavigationController
  ) -> Bool { viewController === destination }
  // PRODUCTION_CAPTURE
  func snapshot(_ coordinator: UIViewControllerTransitionCoordinator?) -> Int? {
    navigationSelectionSession(for: coordinator)
  }
  func acceptsAppearance(_ coordinator: UIViewControllerTransitionCoordinator?) -> Bool {
    // PRODUCTION_QUALIFICATION
    return true
  }
}

private let harness = Harness()
private let cancelled = UIViewControllerTransitionCoordinator()
private let next = UIViewControllerTransitionCoordinator()
private let originalTarget = harness.liveTarget
precondition(harness.snapshot(cancelled) == 1)
harness.skipsNextNavigationSelectionFinalization = true
harness.liveSession = 2
harness.liveTarget = ListNavigationSelectionTarget()
precondition(harness.snapshot(cancelled) == 1, "same transition must retain its original owner")
precondition(harness.navigationSelectionTransitionTarget === originalTarget)
precondition(harness.snapshot(next) == 2, "next transition must not reuse a cancelled session")
precondition(harness.navigationSelectionTransitionTarget === harness.liveTarget)
precondition(!harness.skipsNextNavigationSelectionFinalization, "cancelled appearance cannot skip a future pop")

private let absentSession = UIViewControllerTransitionCoordinator()
harness.liveSession = nil
harness.liveTarget = nil
precondition(harness.snapshot(absentSession) == nil)
harness.liveSession = 3
harness.liveTarget = ListNavigationSelectionTarget()
precondition(harness.snapshot(absentSession) == nil, "nil is captured state, not an uninitialized cache")
precondition(harness.navigationSelectionTransitionTarget == nil)
private let third = UIViewControllerTransitionCoordinator()
precondition(harness.snapshot(third) == 3)
harness.liveSession = 4
precondition(harness.snapshot(nil) == 4, "uncoordinated appearance uses its current owner")

private let page = UIViewController()
page.navigationController = UINavigationController()
harness.navigationSelectionViewController = page
private let outgoing = UIViewControllerTransitionCoordinator()
outgoing.destination = UIViewController()
precondition(!harness.acceptsAppearance(outgoing), "cancelled outgoing pop must not deselect its source")
outgoing.destination = page
precondition(harness.acceptsAppearance(outgoing), "real returning destination must still animate")
precondition(harness.acceptsAppearance(nil), "appearance without coordinator keeps its fallback")
harness.isLegacyIOS = false
outgoing.destination = UIViewController()
precondition(harness.acceptsAppearance(outgoing), "new system qualification stays unchanged")

private let modern = Harness()
modern.isLegacyIOS = false
precondition(modern.snapshot(cancelled) == 1)
modern.liveSession = 2
precondition(modern.snapshot(next) == 1, "new system capture behavior stays unchanged")
print("transition regression passed")

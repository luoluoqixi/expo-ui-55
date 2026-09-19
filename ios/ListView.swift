// Copyright 2025-present 650 Industries. All rights reserved.

import ExpoModulesCore
import SwiftUI

internal enum ListContentInsetAdjustmentBehavior: String, Enumerable {
  case automatic
  case scrollableAxes
  case never
  case always

  var uiKitValue: UIScrollView.ContentInsetAdjustmentBehavior {
    switch self {
    case .automatic:
      return .automatic
    case .scrollableAxes:
      return .scrollableAxes
    case .never:
      return .never
    case .always:
      return .always
    }
  }
}

final class ListProps: UIBaseViewProps {
  @Field var automaticallyAdjustsScrollIndicatorInsets: Bool?
  @Field var compensatesForViewportClipping = false
  @Field var contentInsetAdjustmentBehavior: ListContentInsetAdjustmentBehavior?
  @Field var correctsNestedScrollIndicatorFrame = false
  @Field var clearsNavigationSelectionOnViewWillAppear = false
  @Field var delaysContentTouches = true
  @Field var dismissKeyboardOnTap = false
  @Field var initialScrollAnchor: UnitPointOptions = .center
  @Field var initialScrollTarget: Either<String, Double>?
  @Field var nativeEditMode: EditModeType = .inactive
  @Field var nativeEditTint: Color?
  @Field var refreshEnabled = true
  @Field var refreshable = false
  @Field var refreshing = false
  @Field var scrollPositionRestoreToken = 0
  @Field var selection: [Either<String, Double>]?
  @Field var tracksNavigationBarScrollEdge = false
  fileprivate let scrollPositionStore = ListScrollPositionStore()
  var onRefresh = EventDispatcher()
  var onNavigationSelectionCleared = EventDispatcher()
  var onSelectionChange = EventDispatcher()
}

private final class ListScrollPositionStore {
  weak var scrollView: UIScrollView?
  var hasObservedScrollView = false
  var offset: CGPoint?
}

/// Lets a row control opt into the `List(selection:)` binding before it sends
/// its JS press event. The normal SwiftUI Button pressed appearance otherwise
/// ends one render pass before a controlled React `selection` prop can arrive.
struct ListSelectionActionEnvironmentKey: EnvironmentKey {
  static let defaultValue: (AnyHashable, ListNavigationSelectionTarget?) -> Void = { _, _ in }
}

struct ListSelectionClearActionEnvironmentKey: EnvironmentKey {
  static let defaultValue: (AnyHashable) -> Bool = { _ in false }
}

struct ListSelectionConfirmActionEnvironmentKey: EnvironmentKey {
  static let defaultValue: (AnyHashable) -> Bool = { _ in true }
}

extension EnvironmentValues {
  var expoListSelectionAction: (AnyHashable, ListNavigationSelectionTarget?) -> Void {
    get { self[ListSelectionActionEnvironmentKey.self] }
    set { self[ListSelectionActionEnvironmentKey.self] = newValue }
  }

  var expoListSelectionClearAction: (AnyHashable) -> Bool {
    get { self[ListSelectionClearActionEnvironmentKey.self] }
    set { self[ListSelectionClearActionEnvironmentKey.self] = newValue }
  }

  var expoListSelectionConfirmAction: (AnyHashable) -> Bool {
    get { self[ListSelectionConfirmActionEnvironmentKey.self] }
    set { self[ListSelectionConfirmActionEnvironmentKey.self] = newValue }
  }
}

/// Keeps the UIKit cell even if SwiftUI later loses its selected index path.
final class ListNavigationSelectionTarget {
  private weak var tableView: UITableView?
  private weak var collectionView: UICollectionView?
  private let indexPath: IndexPath

  init(tableView: UITableView, indexPath: IndexPath) {
    self.tableView = tableView
    self.indexPath = indexPath
  }

  init(collectionView: UICollectionView, indexPath: IndexPath) {
    self.collectionView = collectionView
    self.indexPath = indexPath
  }

  func deselect(animated: Bool) {
    if let tableView {
      tableView.cellForRow(at: indexPath)?.isHighlighted = false
      tableView.deselectRow(at: indexPath, animated: animated)
      if !animated {
        tableView.cellForRow(at: indexPath)?.isSelected = false
      }
    }
    if let collectionView {
      collectionView.cellForItem(at: indexPath)?.isHighlighted = false
      collectionView.deselectItem(at: indexPath, animated: animated)
      if !animated {
        collectionView.cellForItem(at: indexPath)?.isSelected = false
      }
    }
  }

  func select() {
    if let tableView {
      tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
      tableView.cellForRow(at: indexPath)?.isSelected = true
      tableView.cellForRow(at: indexPath)?.isHighlighted = true
    }
    if let collectionView {
      collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
      collectionView.cellForItem(at: indexPath)?.isSelected = true
      collectionView.cellForItem(at: indexPath)?.isHighlighted = true
    }
  }

  /// Restore the persistent navigation selection after an interactive pop is
  /// cancelled. A restored row is selected, but it is no longer being touched.
  /// Keeping `isHighlighted` set here leaves a non-interactive highlight above
  /// the selection background, which masks the next transition's deselection.
  func restoreSelection() {
    if let tableView {
      tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
      tableView.cellForRow(at: indexPath)?.isSelected = true
      tableView.cellForRow(at: indexPath)?.isHighlighted = false
    }
    if let collectionView {
      collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
      collectionView.cellForItem(at: indexPath)?.isSelected = true
      collectionView.cellForItem(at: indexPath)?.isHighlighted = false
    }
  }
}

private final class ListSelectionInteractionState {
  private var pendingSelectionID: AnyHashable?
  private var confirmedSelectionID: AnyHashable?
  private var cancelledSelectionID: AnyHashable?
  private var navigationSelectionTarget: ListNavigationSelectionTarget?
  private var isNavigationDeselectInProgress = false

  func begin(_ selectionID: AnyHashable, target: ListNavigationSelectionTarget? = nil) {
    if let previousTarget = navigationSelectionTarget {
      previousTarget.deselect(animated: false)
    }
    pendingSelectionID = selectionID
    confirmedSelectionID = nil
    cancelledSelectionID = nil
    navigationSelectionTarget = target
  }

  func confirm(_ selectionID: AnyHashable) -> Bool {
    guard cancelledSelectionID != selectionID else { return false }
    guard pendingSelectionID == selectionID else { return true }
    confirmedSelectionID = selectionID
    cancelledSelectionID = nil
    return true
  }

  func shouldClearUnconfirmedSelection(_ selectionID: AnyHashable) -> Bool {
    // Cancellation must remain idempotent for the lifetime of this touch.
    // An interactive navigation cancellation can write the id back into the
    // List binding after the first clear, so the transition completion needs
    // to be able to clear the same cancelled interaction again.
    if cancelledSelectionID == selectionID {
      return true
    }
    guard pendingSelectionID == selectionID else { return false }
    pendingSelectionID = nil
    guard confirmedSelectionID != selectionID else { return false }
    cancelledSelectionID = selectionID
    return true
  }

  func shouldRestoreNavigationSelection() -> Bool {
    cancelledSelectionID == nil
  }

  func selectedNavigationTarget() -> ListNavigationSelectionTarget? {
    navigationSelectionTarget
  }

  func beginNavigationDeselect() {
    isNavigationDeselectInProgress = true
  }

  func finishNavigationDeselect() {
    isNavigationDeselectInProgress = false
  }

  func shouldSyncControlledSelectionOnAppear() -> Bool {
    !isNavigationDeselectInProgress
  }

  func removingCancelledSelection(from selection: Set<AnyHashable>) -> Set<AnyHashable> {
    guard let cancelledSelectionID else { return selection }
    return selection.subtracting([cancelledSelectionID])
  }

  func clearNavigationTarget() {
    pendingSelectionID = nil
    confirmedSelectionID = nil
    // Keep the cancelled id until the next `begin`. SwiftUI can write the
    // cancelled List selection back while an interactive transition restores
    // its source hierarchy, even after the UIKit target has been discarded.
    navigationSelectionTarget = nil
  }
}

struct ListView: ExpoSwiftUI.View {
  @ObservedObject var props: ListProps
  @State private var selection = Set<AnyHashable>()
  @State private var hasScrolledToInitialTarget = false
  @State private var selectionInteraction = ListSelectionInteractionState()

  @ViewBuilder
  var body: some View {
    if props.compensatesForViewportClipping {
      GeometryReader { geometry in
        let globalFrame = geometry.frame(in: .global)
        let keyWindow = UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .flatMap { $0.windows }
          .first { $0.isKeyWindow }
        let viewportBottom = keyWindow?.bounds.maxY ?? UIScreen.main.bounds.maxY
        let visibleHeight = max(0, min(globalFrame.height, viewportBottom - globalFrame.minY))
        let indicatorBottomInset = globalFrame.maxY > viewportBottom
          ? (keyWindow?.safeAreaInsets.bottom ?? 0)
          : 0

        if #available(iOS 17.0, tvOS 17.0, *) {
          list
            .contentMargins(.bottom, indicatorBottomInset, for: .scrollIndicators)
            .frame(width: geometry.size.width, height: visibleHeight, alignment: .top)
        } else {
          list
            .frame(width: geometry.size.width, height: visibleHeight, alignment: .top)
        }
      }
    } else {
      list
    }
  }

  private var list: some View {
    ScrollViewReader { proxy in
      List(selection: $selection) {
        Children()
          .environment(\.expoListSelectionAction) { itemID, target in
            selectionInteraction.begin(itemID, target: target)
            selection = [itemID]
          }
          .environment(\.expoListSelectionClearAction) { itemID in
            let shouldClear = selectionInteraction.shouldClearUnconfirmedSelection(itemID)
            if shouldClear {
              if selection == [itemID] {
                selection = []
              }
              return true
            }
            return false
          }
          .environment(\.expoListSelectionConfirmAction) { itemID in
            selectionInteraction.confirm(itemID)
          }
      }
      .background {
        ScrollInsetAdjustmentView(
          automaticallyAdjustsScrollIndicatorInsets: props.automaticallyAdjustsScrollIndicatorInsets ?? true,
          clearsNavigationSelectionOnViewWillAppear: props.clearsNavigationSelectionOnViewWillAppear,
          contentInsetAdjustmentBehavior: props.contentInsetAdjustmentBehavior,
          correctsNestedScrollIndicatorFrame: props.correctsNestedScrollIndicatorFrame,
          delaysContentTouches: props.delaysContentTouches,
          dismissKeyboardOnTap: props.dismissKeyboardOnTap,
          onRefresh: {
            props.onRefresh(["refreshing": true])
          },
          onNavigationSelectionCleared: {
            // Clear the native binding in the same transition-coordinator callback.
            // Waiting for the event to round-trip through React lets SwiftUI
            // reselect the cell after a completed pop, especially after a prior
            // interactive cancellation.
            selectionInteraction.finishNavigationDeselect()
            selection = []
            selectionInteraction.selectedNavigationTarget()?.deselect(animated: false)
            selectionInteraction.clearNavigationTarget()
            props.onNavigationSelectionCleared([:])
          },
          onNavigationSelectionDeselecting: {
            // UIKit owns the interactive visual animation; the binding must stop
            // asserting the selected value before that animation starts. Keep a
            // separate transition flag because SwiftUI can send another onAppear
            // while restoring a previously cancelled native-stack transition.
            selectionInteraction.beginNavigationDeselect()
            selection = []
          },
          onNavigationSelectionRestored: {
            // UIKit reapplies the selected cell when an interactive pop is
            // cancelled. Keep SwiftUI's binding in sync so a second gesture
            // can animate that same cell and a later completed pop clears it.
            selectionInteraction.finishNavigationDeselect()
            selection = Self.getHashableSetFromEither(props.selection)
          },
          selectedNavigationTarget: {
            selectionInteraction.selectedNavigationTarget()
          },
          shouldRestoreNavigationSelection: {
            selectionInteraction.shouldRestoreNavigationSelection()
          },
          controlledNavigationSelectionIsEmpty:
            props.clearsNavigationSelectionOnViewWillAppear
            && Self.getHashableSetFromEither(props.selection).isEmpty,
          refreshEnabled: props.refreshEnabled,
          refreshable: props.refreshable,
          refreshing: props.refreshing,
          scrollPositionRestoreToken: props.scrollPositionRestoreToken,
          scrollPositionStore: props.scrollPositionStore,
          tracksNavigationBarScrollEdge: props.tracksNavigationBarScrollEdge
        )
      }
      .onAppear {
        // A second interactive pop after a cancellation can make SwiftUI report
        // onAppear after UIKit has already started its coordinated deselection.
        // Reasserting the controlled id at that point masks the interactive fade.
        if selectionInteraction.shouldSyncControlledSelectionOnAppear() {
          selection = Self.getHashableSetFromEither(props.selection)
        }
        scrollToInitialTarget(proxy)
      }
      .onChange(of: props.selection) { newValue in
        let newSelection = Self.getHashableSetFromEither(newValue)
        selection = newSelection
        if newSelection.isEmpty {
          selectionInteraction.selectedNavigationTarget()?.deselect(animated: false)
          selectionInteraction.clearNavigationTarget()
        }
      }
      .onChange(of: props.initialScrollTarget) { _ in
        hasScrolledToInitialTarget = false
        scrollToInitialTarget(proxy)
      }
      .onChange(of: selection) { newSelection in
        let filteredSelection = selectionInteraction.removingCancelledSelection(
          from: newSelection
        )
        if filteredSelection != newSelection {
          selection = filteredSelection
          return
        }
        handleSelectionChange(selection: filteredSelection)
      }
    }
  }

  private func scrollToInitialTarget(_ proxy: ScrollViewProxy) {
    let target = Self.getHashableSetFromEither(
      props.initialScrollTarget.map { [$0] }
    ).first

    guard !hasScrolledToInitialTarget, let target else {
      return
    }

    hasScrolledToInitialTarget = true

    DispatchQueue.main.async {
      proxy.scrollTo(target, anchor: props.initialScrollAnchor.toUnitPoint)
    }
  }

  func handleSelectionChange(selection: Set<AnyHashable>) {
    let propsSelection = Self.getHashableSetFromEither(props.selection)
    if propsSelection == selection { return }

    let selectionArray: [Any] = selection.compactMap { value in
      if let stringValue = value as? String {
        return stringValue
      } else if let doubleValue = value as? Double {
        return doubleValue
      }
      return nil
    }
    props.onSelectionChange(["selection": selectionArray])
  }

  private static func getHashableSetFromEither(_ array: [Either<String, Double>]?) -> Set<AnyHashable> {
    guard let array else { return Set() }
    var result = Set<AnyHashable>()
    for item in array {
      if let stringValue: String = item.get() {
        result.insert(stringValue)
      } else if let doubleValue: Double = item.get() {
        result.insert(doubleValue)
      }
    }
    return result
  }
}

private struct ScrollInsetAdjustmentView: UIViewControllerRepresentable {
  let automaticallyAdjustsScrollIndicatorInsets: Bool
  let clearsNavigationSelectionOnViewWillAppear: Bool
  let contentInsetAdjustmentBehavior: ListContentInsetAdjustmentBehavior?
  let correctsNestedScrollIndicatorFrame: Bool
  let delaysContentTouches: Bool
  let dismissKeyboardOnTap: Bool
  let onRefresh: () -> Void
  let onNavigationSelectionCleared: () -> Void
  let onNavigationSelectionDeselecting: () -> Void
  let onNavigationSelectionRestored: () -> Void
  let selectedNavigationTarget: () -> ListNavigationSelectionTarget?
  let shouldRestoreNavigationSelection: () -> Bool
  let controlledNavigationSelectionIsEmpty: Bool
  let refreshEnabled: Bool
  let refreshable: Bool
  let refreshing: Bool
  let scrollPositionRestoreToken: Int
  let scrollPositionStore: ListScrollPositionStore
  let tracksNavigationBarScrollEdge: Bool

  func makeUIViewController(context: Context) -> ScrollInsetAdjustmentViewController {
    let viewController = ScrollInsetAdjustmentViewController()
    let view = viewController.adjustmentView
    view.automaticallyAdjustsScrollIndicatorInsets = automaticallyAdjustsScrollIndicatorInsets
    view.clearsNavigationSelectionOnViewWillAppear = clearsNavigationSelectionOnViewWillAppear
    view.contentInsetAdjustmentBehavior = contentInsetAdjustmentBehavior
    view.correctsNestedScrollIndicatorFrame = correctsNestedScrollIndicatorFrame
    view.delaysContentTouches = delaysContentTouches
    view.dismissKeyboardOnTap = dismissKeyboardOnTap
    view.onRefresh = onRefresh
    view.onNavigationSelectionCleared = onNavigationSelectionCleared
    view.onNavigationSelectionDeselecting = onNavigationSelectionDeselecting
    view.onNavigationSelectionRestored = onNavigationSelectionRestored
    view.selectedNavigationTarget = selectedNavigationTarget
    view.shouldRestoreNavigationSelection = shouldRestoreNavigationSelection
    view.controlledNavigationSelectionIsEmpty = controlledNavigationSelectionIsEmpty
    view.refreshEnabled = refreshEnabled
    view.refreshable = refreshable
    view.refreshing = refreshing
    view.scrollPositionRestoreToken = scrollPositionRestoreToken
    view.scrollPositionStore = scrollPositionStore
    view.tracksNavigationBarScrollEdge = tracksNavigationBarScrollEdge
    view.refreshNavigationTransitionGestureObservation()
    return viewController
  }

  func updateUIViewController(_ uiViewController: ScrollInsetAdjustmentViewController, context: Context) {
    let view = uiViewController.adjustmentView
    view.automaticallyAdjustsScrollIndicatorInsets = automaticallyAdjustsScrollIndicatorInsets
    view.clearsNavigationSelectionOnViewWillAppear = clearsNavigationSelectionOnViewWillAppear
    view.contentInsetAdjustmentBehavior = contentInsetAdjustmentBehavior
    view.correctsNestedScrollIndicatorFrame = correctsNestedScrollIndicatorFrame
    view.delaysContentTouches = delaysContentTouches
    view.dismissKeyboardOnTap = dismissKeyboardOnTap
    view.onRefresh = onRefresh
    view.onNavigationSelectionCleared = onNavigationSelectionCleared
    view.onNavigationSelectionDeselecting = onNavigationSelectionDeselecting
    view.onNavigationSelectionRestored = onNavigationSelectionRestored
    view.selectedNavigationTarget = selectedNavigationTarget
    view.shouldRestoreNavigationSelection = shouldRestoreNavigationSelection
    view.controlledNavigationSelectionIsEmpty = controlledNavigationSelectionIsEmpty
    view.refreshEnabled = refreshEnabled
    view.refreshable = refreshable
    view.refreshing = refreshing
    view.scrollPositionRestoreToken = scrollPositionRestoreToken
    view.scrollPositionStore = scrollPositionStore
    view.tracksNavigationBarScrollEdge = tracksNavigationBarScrollEdge
    view.refreshNavigationTransitionGestureObservation()
  }
}

private final class ScrollInsetAdjustmentViewController: UIViewController {
  let adjustmentView = ScrollInsetAdjustmentUIView()
  private var applicationDidBecomeActiveObserver: NSObjectProtocol?

  override func loadView() {
    adjustmentView.isUserInteractionEnabled = false
    view = adjustmentView
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    startObservingApplicationActivation()
    adjustmentView.refreshNavigationBarScrollEdgeRegistration()
    // The transition coordinator can finish before SwiftUI performs its final
    // cell reconciliation on newer iOS releases. Make the fully appeared screen
    // authoritative so a completed second pop cannot leave a selected row behind.
    adjustmentView.finalizeNavigationSelectionAfterAppearance()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    adjustmentView.deselectNavigationRowAlongsideTransition(
      transitionCoordinator,
      animated: animated
    )
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    adjustmentView.refreshNavigationTransitionGestureObservation()
    stopObservingApplicationActivation()
  }

  deinit {
    stopObservingApplicationActivation()
  }

  private func startObservingApplicationActivation() {
    guard applicationDidBecomeActiveObserver == nil else { return }

    // iOS 15 may discard UINavigationController's content-scroll-view
    // observation while the app is inactive without replaying appearance
    // callbacks when it becomes active again.
    if #available(iOS 16.0, *) {
      return
    }

    applicationDidBecomeActiveObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.adjustmentView.refreshNavigationBarScrollEdgeRegistration()
    }
  }

  private func stopObservingApplicationActivation() {
    guard let applicationDidBecomeActiveObserver else { return }
    NotificationCenter.default.removeObserver(applicationDidBecomeActiveObserver)
    self.applicationDidBecomeActiveObserver = nil
  }
}

private final class ScrollInsetAdjustmentUIView: UIView, UIGestureRecognizerDelegate {
  var automaticallyAdjustsScrollIndicatorInsets = true {
    didSet {
      scheduleUpdate()
    }
  }

  var contentInsetAdjustmentBehavior: ListContentInsetAdjustmentBehavior? {
    didSet {
      scheduleUpdate()
    }
  }

  var correctsNestedScrollIndicatorFrame = false {
    didSet {
      guard oldValue != correctsNestedScrollIndicatorFrame else { return }
      scheduleUpdate()
    }
  }

  var clearsNavigationSelectionOnViewWillAppear = false

  var delaysContentTouches = true {
    didSet {
      guard oldValue != delaysContentTouches else { return }
      scheduleUpdate()
    }
  }

  var dismissKeyboardOnTap = false {
    didSet {
      guard oldValue != dismissKeyboardOnTap else { return }
      scheduleUpdate()
    }
  }

  var refreshEnabled = true {
    didSet {
      guard oldValue != refreshEnabled else { return }
      scheduleUpdate()
    }
  }

  var refreshable = false {
    didSet {
      guard oldValue != refreshable else { return }
      scheduleUpdate()
    }
  }

  var refreshing = false {
    didSet {
      guard oldValue != refreshing else { return }
      scheduleUpdate()
    }
  }

  var onRefresh: (() -> Void)?
  var onNavigationSelectionCleared: (() -> Void)?
  var onNavigationSelectionDeselecting: (() -> Void)?
  var onNavigationSelectionRestored: (() -> Void)?
  var selectedNavigationTarget: (() -> ListNavigationSelectionTarget?)?
  var shouldRestoreNavigationSelection: (() -> Bool)?

  /// SwiftUI's `onChange` can coalesce a controlled `[id] -> []` update with
  /// the List's own selection write. Track that prop edge in the UIKit bridge
  /// as well so a non-navigating tap always releases the real cell selected by
  /// `ListSelectionTouchTrackingUIView`.
  var controlledNavigationSelectionIsEmpty = true {
    didSet {
      if !controlledNavigationSelectionIsEmpty {
        refreshNavigationTransitionGestureObservation()
      }
      guard clearsNavigationSelectionOnViewWillAppear,
        controlledNavigationSelectionIsEmpty,
        !oldValue else {
        return
      }
      clearNavigationSelectionImmediately()
      stopNavigationTransitionGestureObservation()
    }
  }

  var scrollPositionRestoreToken = 0 {
    didSet {
      guard oldValue != scrollPositionRestoreToken else { return }
      pendingScrollPositionRestore = true
      scheduleUpdate()
    }
  }

  var scrollPositionStore: ListScrollPositionStore? {
    didSet {
      scheduleUpdate()
    }
  }

  var tracksNavigationBarScrollEdge = false {
    didSet {
      guard oldValue != tracksNavigationBarScrollEdge else { return }
      if tracksNavigationBarScrollEdge {
        refreshNavigationBarScrollEdgeRegistration()
      } else {
        scheduleUpdate()
      }
    }
  }

  private weak var configuredScrollView: UIScrollView?
  private weak var keyboardDismissScrollView: UIScrollView?
  private weak var configuredViewController: UIViewController?
  private weak var correctedIndicatorScrollView: UIScrollView?
  private weak var observedAncestorScrollView: UIScrollView?
  private weak var registeredContentScrollView: UIScrollView?
  private var ancestorContentOffsetObservation: NSKeyValueObservation?
  private var indicatorBoundsObservation: NSKeyValueObservation?
  private var indicatorContentOffsetObservation: NSKeyValueObservation?
  private var indicatorContentSizeObservation: NSKeyValueObservation?
  private var scrollPositionObservation: NSKeyValueObservation?
  private var pendingScrollPositionRestore = false
  private var ios15ContentOffsetObservation: NSKeyValueObservation?
  private weak var ios15ObservedContentScrollView: UIScrollView?
  private var indicatorFrameCorrectionScheduled = false
  private var updateScheduled = false
  private var forceContentScrollViewRegistration = false
  private var registrationRetryAttemptsRemaining = 0
  private var registrationRetryScheduled = false
  private weak var navigationSelectionViewController: UIViewController?
  private var navigationTransitionGestureRecognizers: [UIGestureRecognizer] = []
  private var activeNavigationTransitionIdentifier: ObjectIdentifier?
  private var skipsNextNavigationSelectionFinalization = false

  /// UIKit owns the cell-selection visual state. Deselecting its actual table or
  /// collection cell inside the screen transition coordinator makes the highlight
  /// scrub with an interactive back gesture instead of jumping at its completion.
  func deselectNavigationRowAlongsideTransition(
    _ coordinator: UIViewControllerTransitionCoordinator?,
    animated: Bool
  ) {
    guard clearsNavigationSelectionOnViewWillAppear else { return }
    guard #available(iOS 16.0, tvOS 16.0, *) else { return }
    let navigationRows = selectedNavigationRows
    guard !navigationRows.isEmpty else { return }

    let transitionIdentifier = coordinator.map { ObjectIdentifier($0 as AnyObject) }
    if let transitionIdentifier,
      activeNavigationTransitionIdentifier == transitionIdentifier {
      return
    }
    activeNavigationTransitionIdentifier = transitionIdentifier
    let shouldAnimate = animated || coordinator?.isAnimated == true

    let deselect = { [weak self] in
      guard let self else { return }
      for navigationRow in navigationRows {
        self.deselectNavigationRow(navigationRow, animated: shouldAnimate)
      }
      // Let UIKit begin the native cell deselection while the row is still
      // selected. Clearing SwiftUI's binding first removes the only animatable
      // state, which is why a restored row stayed at a fixed color on the next
      // interactive pop.
      self.onNavigationSelectionDeselecting?()
    }

    guard let coordinator else {
      deselect()
      onNavigationSelectionCleared?()
      return
    }

    coordinator.animate(alongsideTransition: { _ in
      deselect()
    }, completion: { [weak self] context in
      guard let self else { return }
      self.activeNavigationTransitionIdentifier = nil
      if context.isCancelled {
        self.skipsNextNavigationSelectionFinalization = true
        // The passive touch observer resolves whether SwiftUI's Button action
        // actually fired 30ms after touch-up. Wait for that result before
        // deciding whether a cancelled transition should restore this row.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
          guard let self else { return }
          if self.shouldRestoreNavigationSelection?() == false {
            for navigationRow in navigationRows + self.visibleNavigationRows {
              self.deselectNavigationRow(navigationRow, animated: false)
            }
            self.onNavigationSelectionCleared?()
            return
          }
          // UIKit can finish its own cancellation bookkeeping immediately after
          // the coordinator completion callback. Restore after that bookkeeping.
          for navigationRow in navigationRows {
            self.selectNavigationRow(navigationRow)
          }
          DispatchQueue.main.async {
            for navigationRow in navigationRows {
              self.selectNavigationRow(navigationRow)
            }
            self.onNavigationSelectionRestored?()
          }
        }
      } else {
        self.skipsNextNavigationSelectionFinalization = false
        // SwiftUI may reconcile the cell once more during the last transition
        // frame. Make the completed state authoritative before notifying React.
        self.deselectNavigationRowsAfterSystemReconciliation(navigationRows)
        self.onNavigationSelectionCleared?()
      }
    })
  }

  /// `UIViewControllerRepresentable` children do not receive another
  /// `viewWillAppear` when a native-stack interactive pop is cancelled and a
  /// second pop starts. Observe the navigation controller's existing pan
  /// recognizers as passive targets so every interactive transition can join
  /// the same UIKit deselection animation. Adding a target does not change any
  /// recognizer delegate or touch-cancellation behavior.
  func refreshNavigationTransitionGestureObservation() {
#if !os(tvOS)
    guard clearsNavigationSelectionOnViewWillAppear,
      !controlledNavigationSelectionIsEmpty else {
      return
    }
    guard let viewController = navigationSelectionViewController ?? findContentViewController(),
      let navigationController = viewController.navigationController else {
      return
    }
    navigationSelectionViewController = viewController

    var candidates: [UIGestureRecognizer] = []
    if let interactivePopGestureRecognizer = navigationController.interactivePopGestureRecognizer {
      candidates.append(interactivePopGestureRecognizer)
    }
    candidates.append(contentsOf: navigationTransitionPanGestureRecognizers(in: navigationController.view))

    var existing = Set(navigationTransitionGestureRecognizers.map(ObjectIdentifier.init))
    for gestureRecognizer in candidates
      where existing.insert(ObjectIdentifier(gestureRecognizer)).inserted {
      gestureRecognizer.addTarget(
        self,
        action: #selector(handleNavigationTransitionGesture(_:))
      )
      navigationTransitionGestureRecognizers.append(gestureRecognizer)
    }
#endif
  }

#if !os(tvOS)
  private func navigationTransitionPanGestureRecognizers(in view: UIView) -> [UIGestureRecognizer] {
    var result = (view.gestureRecognizers ?? []).filter { gestureRecognizer in
      guard gestureRecognizer is UIPanGestureRecognizer else { return false }
      if gestureRecognizer is UIScreenEdgePanGestureRecognizer { return true }
      let className = String(describing: type(of: gestureRecognizer))
      return className.contains("Transition") ||
        (className.contains("RNS") && className.contains("Pan"))
    }
    for subview in view.subviews {
      result.append(contentsOf: navigationTransitionPanGestureRecognizers(in: subview))
    }
    return result
  }

  @objc private func handleNavigationTransitionGesture(_ gestureRecognizer: UIGestureRecognizer) {
    guard gestureRecognizer.state == .began || gestureRecognizer.state == .changed else { return }
    beginObservedInteractiveNavigationTransitionIfNeeded()
    if gestureRecognizer.state == .began {
      // React Native Screens can install the transition coordinator from a
      // later target-action callback on the same gesture update.
      DispatchQueue.main.async { [weak self] in
        self?.beginObservedInteractiveNavigationTransitionIfNeeded()
      }
    }
  }

  private func beginObservedInteractiveNavigationTransitionIfNeeded() {
    guard let viewController = navigationSelectionViewController,
      let coordinator = viewController.navigationController?.transitionCoordinator,
      coordinator.initiallyInteractive,
      let destinationViewController = coordinator.viewController(forKey: .to),
      sharesViewControllerHierarchy(viewController, destinationViewController) else {
      return
    }
    deselectNavigationRowAlongsideTransition(coordinator, animated: true)
  }

  private func sharesViewControllerHierarchy(
    _ first: UIViewController,
    _ second: UIViewController
  ) -> Bool {
    var current: UIViewController? = first
    while let viewController = current {
      if viewController === second { return true }
      current = viewController.parent
    }
    current = second
    while let viewController = current {
      if viewController === first { return true }
      current = viewController.parent
    }
    return false
  }
#endif

  private func stopNavigationTransitionGestureObservation() {
#if !os(tvOS)
    for gestureRecognizer in navigationTransitionGestureRecognizers {
      gestureRecognizer.removeTarget(
        self,
        action: #selector(handleNavigationTransitionGesture(_:))
      )
    }
    navigationTransitionGestureRecognizers.removeAll()
#endif
  }

  func finalizeNavigationSelectionAfterAppearance() {
    guard clearsNavigationSelectionOnViewWillAppear else { return }
    guard #available(iOS 16.0, tvOS 16.0, *) else { return }
    if skipsNextNavigationSelectionFinalization {
      skipsNextNavigationSelectionFinalization = false
      return
    }
    clearNavigationSelectionImmediately()
    // iOS can perform one final SwiftUI cell reconciliation after the child
    // controller's appearance callback. Inspect the live cells again after
    // that pass so a completed pop following a cancelled pop cannot reselect it.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      for navigationRow in self.selectedNavigationRows {
        self.deselectNavigationRow(navigationRow, animated: false)
      }
    }
  }

  private func deselectNavigationRowsAfterSystemReconciliation(
    _ transitionRows: [NavigationRowSelection]
  ) {
    let clear = { [weak self] in
      guard let self else { return }
      for navigationRow in transitionRows + self.visibleNavigationRows {
        self.deselectNavigationRow(navigationRow, animated: false)
      }
    }
    clear()
    // The completion can precede SwiftUI's last collection-cell update on
    // newer OS releases. Clear on the next main-loop turn as well.
    DispatchQueue.main.async(execute: clear)
  }

  private func clearNavigationSelectionImmediately() {
    let navigationRows = selectedNavigationRows
    for navigationRow in navigationRows {
      deselectNavigationRow(navigationRow, animated: false)
    }
    guard !navigationRows.isEmpty else { return }
    onNavigationSelectionCleared?()
  }

  private enum NavigationRowSelection {
    case table(UITableView, IndexPath)
    case collection(UICollectionView, IndexPath)
    case target(ListNavigationSelectionTarget)
  }

  private struct NavigationRowSelectionKey: Hashable {
    let scrollView: ObjectIdentifier
    let indexPath: IndexPath
  }

  private var selectedNavigationRows: [NavigationRowSelection] {
    var result: [NavigationRowSelection] = []
    var seen = Set<NavigationRowSelectionKey>()

    let appendTableRow = { (tableView: UITableView, indexPath: IndexPath) in
      let key = NavigationRowSelectionKey(
        scrollView: ObjectIdentifier(tableView),
        indexPath: indexPath
      )
      guard seen.insert(key).inserted else { return }
      result.append(.table(tableView, indexPath))
    }
    let appendCollectionRow = { (collectionView: UICollectionView, indexPath: IndexPath) in
      let key = NavigationRowSelectionKey(
        scrollView: ObjectIdentifier(collectionView),
        indexPath: indexPath
      )
      guard seen.insert(key).inserted else { return }
      result.append(.collection(collectionView, indexPath))
    }

    let scrollView = configuredScrollView ?? findListScrollView()
    if let tableView = scrollView as? UITableView,
      let indexPath = tableView.indexPathForSelectedRow {
      appendTableRow(tableView, indexPath)
    }
    if let collectionView = scrollView as? UICollectionView {
      for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
        appendCollectionRow(collectionView, indexPath)
      }
    }
    for navigationRow in visibleNavigationRows {
      switch navigationRow {
      case let .table(tableView, indexPath):
        appendTableRow(tableView, indexPath)
      case let .collection(collectionView, indexPath):
        appendCollectionRow(collectionView, indexPath)
      case .target:
        break
      }
    }
    if result.isEmpty, let target = selectedNavigationTarget?() {
      result.append(.target(target))
    }
    return result
  }

  /// SwiftUI can recreate its collection cell while the source screen is
  /// detached. The saved target then points at the old cell even though the new
  /// visible cell still carries `isHighlighted`. Always inspect the live cells
  /// as well as UIKit's selected-index-path bookkeeping.
  private var visibleNavigationRows: [NavigationRowSelection] {
    let scrollView = configuredScrollView ?? findListScrollView()
    if let tableView = scrollView as? UITableView {
      return tableView.visibleCells.compactMap { cell in
        guard (cell.isSelected || cell.isHighlighted),
          let indexPath = tableView.indexPath(for: cell) else {
          return nil
        }
        return .table(tableView, indexPath)
      }
    }
    if let collectionView = scrollView as? UICollectionView {
      return collectionView.visibleCells.compactMap { cell in
        guard (cell.isSelected || cell.isHighlighted),
          let indexPath = collectionView.indexPath(for: cell) else {
          return nil
        }
        return .collection(collectionView, indexPath)
      }
    }
    return []
  }

  private func deselectNavigationRow(_ navigationRow: NavigationRowSelection, animated: Bool) {
    switch navigationRow {
    case let .table(tableView, indexPath):
      tableView.cellForRow(at: indexPath)?.isHighlighted = false
      tableView.deselectRow(at: indexPath, animated: animated)
      if !animated {
        tableView.cellForRow(at: indexPath)?.isSelected = false
      }
    case let .collection(collectionView, indexPath):
      collectionView.cellForItem(at: indexPath)?.isHighlighted = false
      collectionView.deselectItem(at: indexPath, animated: animated)
      if !animated {
        collectionView.cellForItem(at: indexPath)?.isSelected = false
      }
    case let .target(target):
      target.deselect(animated: animated)
    }
  }

  private func selectNavigationRow(_ navigationRow: NavigationRowSelection) {
    switch navigationRow {
    case let .table(tableView, indexPath):
      tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
      tableView.cellForRow(at: indexPath)?.isSelected = true
      tableView.cellForRow(at: indexPath)?.isHighlighted = false
    case let .collection(collectionView, indexPath):
      collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
      collectionView.cellForItem(at: indexPath)?.isSelected = true
      collectionView.cellForItem(at: indexPath)?.isHighlighted = false
    case let .target(target):
      target.restoreSelection()
    }
  }

  deinit {
    stopNavigationTransitionGestureObservation()
  }

  private lazy var keyboardDismissTapGestureRecognizer: UITapGestureRecognizer = {
    let recognizer = UITapGestureRecognizer(
      target: self,
      action: #selector(handleKeyboardDismissTap)
    )
    recognizer.cancelsTouchesInView = false
    recognizer.delaysTouchesBegan = false
    recognizer.delaysTouchesEnded = false
    recognizer.delegate = self
    return recognizer
  }()

  private static let maximumRegistrationRetryAttempts = 30

  private lazy var nativeRefreshControl: UIRefreshControl = {
    let refreshControl = UIRefreshControl()
    refreshControl.addTarget(
      self,
      action: #selector(handleNativeRefresh),
      for: .valueChanged
    )
    return refreshControl
  }()

  func refreshNavigationBarScrollEdgeRegistration() {
    registrationRetryAttemptsRemaining = Self.maximumRegistrationRetryAttempts
    scheduleUpdate(forceContentScrollViewRegistration: true)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()

    if window == nil {
      stopNestedScrollIndicatorFrameCorrection()
      removeKeyboardDismissTapGestureRecognizer()

      // 被同一 UINavigationController 中的下一页暂时覆盖时，保留内容滚动视图关联，
      // 让返回动画从当前折叠/展开状态开始；真正离开导航栈时仍按原逻辑注销。
      if !preservesContentScrollViewWhileScreenIsDetached {
        unregisterContentScrollView()
      }
    } else {
      refreshNavigationBarScrollEdgeRegistration()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    if configuredScrollView?.window == nil {
      stopNestedScrollIndicatorFrameCorrection()
      removeKeyboardDismissTapGestureRecognizer()

      if !preservesContentScrollViewWhileScreenIsDetached {
        unregisterContentScrollView()
        configuredScrollView = nil
        scheduleUpdate()
      }
    } else if correctsNestedScrollIndicatorFrame {
      scheduleUpdate()
    }
  }

  private var preservesContentScrollViewWhileScreenIsDetached: Bool {
    if clearsNavigationSelectionOnViewWillAppear && configuredScrollView != nil {
      return true
    }
    return tracksNavigationBarScrollEdge &&
      configuredScrollView != nil &&
      registeredContentScrollView != nil &&
      configuredViewController?.navigationController != nil
  }

  private func scheduleUpdate(forceContentScrollViewRegistration: Bool = false) {
    self.forceContentScrollViewRegistration =
      self.forceContentScrollViewRegistration || forceContentScrollViewRegistration
    guard !updateScheduled else { return }
    updateScheduled = true

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.updateScheduled = false
      self.applyAdjustment()
    }
  }

  private func applyAdjustment() {
    guard window != nil else { return }
    guard let scrollView = configuredScrollView ?? findListScrollView() else { return }

    if clearsNavigationSelectionOnViewWillAppear {
      navigationSelectionViewController = findContentViewController()
      refreshNavigationTransitionGestureObservation()
    }

    let replacesPreviousScrollView =
      scrollPositionStore?.hasObservedScrollView == true &&
      scrollPositionStore?.scrollView !== scrollView

    configuredScrollView = scrollView
    let forceRegistration = forceContentScrollViewRegistration
    forceContentScrollViewRegistration = false
    let shouldRestoreScrollPosition = replacesPreviousScrollView || pendingScrollPositionRestore
    pendingScrollPositionRestore = false
    var needsLayout = false

    if scrollView.automaticallyAdjustsScrollIndicatorInsets != automaticallyAdjustsScrollIndicatorInsets {
      scrollView.automaticallyAdjustsScrollIndicatorInsets = automaticallyAdjustsScrollIndicatorInsets
      needsLayout = true
    }

    if let contentInsetAdjustmentBehavior,
      scrollView.contentInsetAdjustmentBehavior != contentInsetAdjustmentBehavior.uiKitValue {
      scrollView.contentInsetAdjustmentBehavior = contentInsetAdjustmentBehavior.uiKitValue
      needsLayout = true
    }

    if scrollView.delaysContentTouches != delaysContentTouches {
      scrollView.delaysContentTouches = delaysContentTouches
    }

    if needsLayout {
      scrollView.setNeedsLayout()
    }

    observeScrollPosition(of: scrollView, restore: shouldRestoreScrollPosition)

    updateNestedScrollIndicatorFrameCorrection(for: scrollView)
    updateContentScrollViewRegistration(scrollView, force: forceRegistration)
    updateKeyboardDismissTapGestureRecognizer(for: scrollView)
    updateNativeRefreshControl(for: scrollView)
  }

  private func updateNativeRefreshControl(for scrollView: UIScrollView) {
    guard refreshable else {
      if scrollView.refreshControl === nativeRefreshControl {
        nativeRefreshControl.endRefreshing()
        scrollView.refreshControl = nil
      }
      return
    }

    if scrollView.refreshControl !== nativeRefreshControl {
      scrollView.refreshControl = nativeRefreshControl
    }

    nativeRefreshControl.isEnabled = refreshEnabled
    nativeRefreshControl.isHidden = !refreshEnabled

    if !refreshEnabled || !refreshing {
      nativeRefreshControl.endRefreshing()
    } else if !nativeRefreshControl.isRefreshing {
      nativeRefreshControl.beginRefreshing()
    }
  }

  @objc private func handleNativeRefresh() {
    guard refreshEnabled else {
      nativeRefreshControl.endRefreshing()
      return
    }
    onRefresh?()
  }

  private func updateKeyboardDismissTapGestureRecognizer(for scrollView: UIScrollView) {
    guard dismissKeyboardOnTap else {
      removeKeyboardDismissTapGestureRecognizer()
      return
    }

    if keyboardDismissScrollView !== scrollView {
      removeKeyboardDismissTapGestureRecognizer()
      scrollView.addGestureRecognizer(keyboardDismissTapGestureRecognizer)
      keyboardDismissScrollView = scrollView
    }
  }

  private func removeKeyboardDismissTapGestureRecognizer() {
    keyboardDismissScrollView?.removeGestureRecognizer(keyboardDismissTapGestureRecognizer)
    keyboardDismissScrollView = nil
  }

  @objc private func handleKeyboardDismissTap() {
    window?.endEditing(true)
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    guard gestureRecognizer === keyboardDismissTapGestureRecognizer else { return true }

    // iOS 15 的 SwiftUI List 由 UITableView 驱动。若让用于空白区域的
    // 键盘收起手势同时识别 cell 内的 Button 点击，`endEditing` 会与
    // UITableView 的 deferred row selection 处于同一轮提交，可能触发
    // SwiftUI 的内部 trap。iOS 16+ 不使用该 UITableView List 路径，
    // 保持既有行为不变。
    if #available(iOS 16.0, tvOS 16.0, *) {
      return true
    }

    var touchedView = touch.view
    while let currentView = touchedView {
      if currentView is UITextField || currentView is UITextView {
        return false
      }
      if currentView is UITableViewCell {
        return false
      }
      if currentView === keyboardDismissScrollView {
        break
      }
      touchedView = currentView.superview
    }
    return true
  }

  private func observeScrollPosition(of scrollView: UIScrollView, restore: Bool) {
    guard let scrollPositionStore else { return }
    if scrollPositionStore.scrollView === scrollView, restore,
      let savedOffset = scrollPositionStore.offset {
      restoreScrollPosition(savedOffset, in: scrollView, attemptsRemaining: 8)
      return
    }
    guard scrollPositionStore.scrollView !== scrollView else { return }

    scrollPositionObservation = nil
    let savedOffset = scrollPositionStore.offset
    scrollPositionStore.scrollView = scrollView
    scrollPositionStore.hasObservedScrollView = true

    if restore, let savedOffset {
      restoreScrollPosition(savedOffset, in: scrollView, attemptsRemaining: 8)
    }

    scrollPositionObservation = scrollView.observe(\.contentOffset, options: [.new]) {
      [weak scrollPositionStore, weak scrollView] _, _ in
      guard let scrollPositionStore, let scrollView else { return }
      let offset = scrollView.contentOffset
      let topOffset = -scrollView.adjustedContentInset.top
      if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating ||
        abs(offset.y - topOffset) >= 0.5 {
        scrollPositionStore.offset = offset
      }
    }
  }

  private func restoreScrollPosition(
    _ offset: CGPoint,
    in scrollView: UIScrollView,
    attemptsRemaining: Int
  ) {
    guard attemptsRemaining > 0 else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak scrollView] in
      guard let self, let scrollView,
        self.scrollPositionStore?.scrollView === scrollView else {
        return
      }
      scrollView.setContentOffset(offset, animated: false)
      self.restoreScrollPosition(offset, in: scrollView, attemptsRemaining: attemptsRemaining - 1)
    }
  }

  private func updateNestedScrollIndicatorFrameCorrection(for scrollView: UIScrollView) {
    guard correctsNestedScrollIndicatorFrame else {
      stopNestedScrollIndicatorFrameCorrection()
      return
    }

    if correctedIndicatorScrollView !== scrollView {
      stopNestedScrollIndicatorFrameCorrection()
      correctedIndicatorScrollView = scrollView
      startObservingIndicatorGeometry(of: scrollView)
    }

    observeAncestorScrollView(of: scrollView)
    scheduleIndicatorFrameCorrection(for: scrollView)
  }

  private func startObservingIndicatorGeometry(of scrollView: UIScrollView) {
    indicatorBoundsObservation = scrollView.observe(
      \.bounds,
      options: [.new]
    ) { [weak self, weak scrollView] _, _ in
      guard let self, let scrollView else { return }
      self.scheduleIndicatorFrameCorrection(for: scrollView)
    }
    indicatorContentOffsetObservation = scrollView.observe(
      \.contentOffset,
      options: [.new]
    ) { [weak self, weak scrollView] _, _ in
      guard let self, let scrollView else { return }
      self.scheduleIndicatorFrameCorrection(for: scrollView)
    }
    indicatorContentSizeObservation = scrollView.observe(
      \.contentSize,
      options: [.new]
    ) { [weak self, weak scrollView] _, _ in
      guard let self, let scrollView else { return }
      self.scheduleIndicatorFrameCorrection(for: scrollView)
    }
  }

  private func scheduleIndicatorFrameCorrection(for scrollView: UIScrollView) {
    guard !indicatorFrameCorrectionScheduled else { return }
    indicatorFrameCorrectionScheduled = true

    // UIScrollView lays out its private indicator after publishing contentOffset.
    // Correct on the next main-loop turn so the opt-in frame wins that layout pass.
    DispatchQueue.main.async { [weak self, weak scrollView] in
      guard let self else { return }
      self.indicatorFrameCorrectionScheduled = false
      guard let scrollView,
        self.correctedIndicatorScrollView === scrollView,
        self.correctsNestedScrollIndicatorFrame else {
        return
      }
      self.correctVerticalIndicatorFrame(in: scrollView)
    }
  }

  private func correctVerticalIndicatorFrame(in scrollView: UIScrollView) {
    guard let indicatorView = findVerticalIndicatorView(in: scrollView) else { return }

    let indicatorInsets = scrollView.verticalScrollIndicatorInsets
    let adjustedInsets = scrollView.adjustedContentInset
    let trackPadding: CGFloat = 3
    let minimumThumbLength: CGFloat = 7
    let trackLength = max(
      0,
      scrollView.bounds.height -
        indicatorInsets.top -
        indicatorInsets.bottom -
        trackPadding * 2
    )
    let visibleContentLength = max(
      0,
      scrollView.bounds.height - adjustedInsets.top - adjustedInsets.bottom
    )
    let totalContentLength = max(
      visibleContentLength,
      scrollView.contentSize.height + adjustedInsets.top + adjustedInsets.bottom
    )
    guard trackLength > 0, totalContentLength > 0 else { return }

    let thumbLength = min(
      trackLength,
      max(minimumThumbLength, trackLength * visibleContentLength / totalContentLength)
    )
    let minimumOffset = -adjustedInsets.top
    let maximumOffset = max(
      minimumOffset,
      scrollView.contentSize.height - scrollView.bounds.height + adjustedInsets.bottom
    )
    let offsetRange = maximumOffset - minimumOffset
    let progress = offsetRange > 0
      ? min(1, max(0, (scrollView.contentOffset.y - minimumOffset) / offsetRange))
      : 0
    let trackTop = scrollView.contentOffset.y + indicatorInsets.top + trackPadding
    let thumbOriginY = trackTop + (trackLength - thumbLength) * progress
    let expectedFrame = CGRect(
      x: indicatorView.frame.origin.x,
      y: thumbOriginY,
      width: indicatorView.frame.width,
      height: thumbLength
    )

    if abs(indicatorView.frame.minY - expectedFrame.minY) > 0.5 ||
      abs(indicatorView.frame.height - expectedFrame.height) > 0.5 {
      indicatorView.frame = expectedFrame
    }
  }

  private func findVerticalIndicatorView(in scrollView: UIScrollView) -> UIView? {
    scrollView.subviews.first { subview in
      let frame = subview.frame
      return frame.width > 0 &&
        frame.width <= 8 &&
        frame.height >= frame.width &&
        frame.maxX >= scrollView.bounds.width - 16
    }
  }

  private func observeAncestorScrollView(of scrollView: UIScrollView) {
    let ancestorScrollView = findAncestorScrollView(of: scrollView)
    guard observedAncestorScrollView !== ancestorScrollView else { return }

    ancestorContentOffsetObservation = nil
    observedAncestorScrollView = ancestorScrollView
    guard let ancestorScrollView else { return }

    ancestorContentOffsetObservation = ancestorScrollView.observe(
      \.contentOffset,
      options: [.new]
    ) { [weak self, weak scrollView] _, _ in
      guard let self, let scrollView else { return }
      self.scheduleIndicatorFrameCorrection(for: scrollView)
    }
  }

  private func findAncestorScrollView(of scrollView: UIScrollView) -> UIScrollView? {
    var ancestor = scrollView.superview
    while let current = ancestor {
      if let ancestorScrollView = current as? UIScrollView {
        return ancestorScrollView
      }
      ancestor = current.superview
    }
    return nil
  }

  private func stopNestedScrollIndicatorFrameCorrection() {
    ancestorContentOffsetObservation = nil
    indicatorBoundsObservation = nil
    indicatorContentOffsetObservation = nil
    indicatorContentSizeObservation = nil
    observedAncestorScrollView = nil
    indicatorFrameCorrectionScheduled = false

    if let scrollView = correctedIndicatorScrollView {
      scrollView.setNeedsLayout()
    }

    correctedIndicatorScrollView = nil
  }

  private func updateContentScrollViewRegistration(_ scrollView: UIScrollView, force: Bool) {
    guard tracksNavigationBarScrollEdge else {
      unregisterContentScrollView()
      return
    }

    guard let viewController = findContentViewController() else {
      if configuredViewController != nil {
        unregisterContentScrollView()
      }
      scheduleContentViewControllerRegistrationRetry()
      return
    }

    registrationRetryAttemptsRemaining = 0

    if configuredViewController !== viewController {
      unregisterContentScrollView()
    }

    configuredViewController = viewController
    if force, viewController.contentScrollView(for: .top) === scrollView {
      viewController.setContentScrollView(nil, for: .top)
    }
    if force || viewController.contentScrollView(for: .top) !== scrollView {
      viewController.setContentScrollView(scrollView, for: .top)
      viewController.navigationController?.navigationBar.setNeedsLayout()
    }
    registeredContentScrollView = scrollView
    updateIos15LargeTitleScrollTracking(for: scrollView)
  }

  private func updateIos15LargeTitleScrollTracking(for scrollView: UIScrollView) {
#if os(tvOS)
    return
#else
    if #available(iOS 16.0, *) {
      stopIos15LargeTitleScrollTracking()
      return
    }

    guard ios15ObservedContentScrollView !== scrollView else { return }
    stopIos15LargeTitleScrollTracking()
    ios15ObservedContentScrollView = scrollView
    ios15ContentOffsetObservation = scrollView.observe(
      \.contentOffset,
      options: [.new]
    ) { [weak self, weak scrollView] _, _ in
      guard let self, let scrollView else { return }
      self.invalidateIos15LargeTitleLayout(for: scrollView)
    }
#endif
  }

  private func invalidateIos15LargeTitleLayout(for scrollView: UIScrollView) {
#if !os(tvOS)
    if #available(iOS 16.0, *) { return }
    guard window != nil,
      ios15ObservedContentScrollView === scrollView,
      usesLargeTitle,
      let viewController = configuredViewController,
      let navigationController = viewController.navigationController else {
      return
    }

    // SwiftUI's iOS 15 UITableView can miss the navigation controller's
    // content-offset invalidation during a large-title transition. Preserve the
    // existing association and only restore it if another container replaced it.
    if viewController.contentScrollView(for: .top) !== scrollView {
      viewController.setContentScrollView(scrollView, for: .top)
    }
    navigationController.view.setNeedsLayout()
    navigationController.navigationBar.setNeedsLayout()
#endif
  }

  private func stopIos15LargeTitleScrollTracking() {
    ios15ContentOffsetObservation = nil
    ios15ObservedContentScrollView = nil
  }

  private var usesLargeTitle: Bool {
#if os(tvOS)
    return false
#else
    if #available(iOS 16.0, *) {
      return false
    }
    guard let viewController = configuredViewController,
      let navigationBar = viewController.navigationController?.navigationBar else {
      return false
    }
    return navigationBar.prefersLargeTitles &&
      viewController.navigationItem.largeTitleDisplayMode != .never
#endif
  }

  private func scheduleContentViewControllerRegistrationRetry() {
    guard window != nil,
      tracksNavigationBarScrollEdge,
      registrationRetryAttemptsRemaining > 0,
      !registrationRetryScheduled else {
      return
    }

    registrationRetryAttemptsRemaining -= 1
    registrationRetryScheduled = true

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      guard let self else { return }
      self.registrationRetryScheduled = false
      self.scheduleUpdate(forceContentScrollViewRegistration: true)
    }
  }

  private func unregisterContentScrollView() {
    stopIos15LargeTitleScrollTracking()
    guard let viewController = configuredViewController else { return }

    if viewController.contentScrollView(for: .top) === registeredContentScrollView {
      viewController.setContentScrollView(nil, for: .top)
    }
    configuredViewController = nil
    registeredContentScrollView = nil
  }

  private func findContentViewController() -> UIViewController? {
    var responder: UIResponder? = self

    while let current = responder {
      if let hostingViewController = current as? UIViewController {
        var contentViewController = hostingViewController

        while let parent = contentViewController.parent,
          !(parent is UINavigationController),
          !(parent is UITabBarController) {
          contentViewController = parent
        }

        guard contentViewController.navigationController != nil ||
          contentViewController.parent is UINavigationController else {
          return nil
        }
        return contentViewController
      }
      responder = current.next
    }

    return nil
  }

  private func findListScrollView() -> UIScrollView? {
    var ancestor: UIView? = superview

    while let current = ancestor {
      if let listScrollView = findListScrollView(in: current) {
        return listScrollView
      }
      ancestor = current.superview
    }

    return nil
  }

  private func findListScrollView(in view: UIView) -> UIScrollView? {
    // SwiftUI List is backed by UITableView on iOS 15 and UICollectionView on
    // newer systems. Both are UIScrollView subclasses and can drive UIKit's
    // navigation-bar scroll-edge appearance.
    if let tableView = view as? UITableView {
      return tableView
    }

    if let collectionView = view as? UICollectionView {
      return collectionView
    }

    for child in view.subviews {
      if let listScrollView = findListScrollView(in: child) {
        return listScrollView
      }
    }

    return nil
  }
}

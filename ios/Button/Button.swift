// Copyright 2025-present 650 Industries. All rights reserved.

import SwiftUI
import UIKit
import ExpoModulesCore
import CoreFoundation

private enum ListSelectionTouchDiagnostics {
  static func log(_ message: @autoclosure () -> String) {
    #if DEBUG
    guard ProcessInfo.processInfo.environment["EXPO_UI_LIST_TOUCH_DEBUG"] == "1" else { return }
    NSLog("[ExpoUI.ListTouch] %@", message())
    #endif
  }
}

public struct Button: ExpoSwiftUI.View {
  @ObservedObject public var props: ButtonProps
  @Environment(\.expoListSelectionAction) private var selectListItem
  @Environment(\.expoListSelectionClearAction) private var clearListItem
  @Environment(\.expoListSelectionConfirmAction) private var confirmListItem
  @Environment(\.expoListSelectionTarget) private var listSelectionTarget
  @State private var selectionTouchState = ListSelectionTouchState()

  public init(props: ButtonProps) {
    self.props = props
  }

  public var body: some View {
    if let label = props.label {
      if let systemImage = props.systemImage {
        navigationSelectionTracking(SwiftUI.Button(label, systemImage: systemImage, role: props.role?.toNativeRole()) {
          handlePress()
        })
      } else {
        navigationSelectionTracking(SwiftUI.Button(label, role: props.role?.toNativeRole()) {
          handlePress()
        })
      }
    } else {
      navigationSelectionTracking(SwiftUI.Button(role: props.role?.toNativeRole(), action: {
        handlePress()
      }) {
        Children()
      })
    }
  }

  private func handlePress() {
    if let selectionID = listSelectionID {
      // A competing scroll or back-pan gesture can make SwiftUI dispatch the
      // action late even though the row interaction was already cancelled.
      let session = selectionTouchState.sessionForButtonAction()
      let confirmed = confirmListItem(selectionID, session)
      ListSelectionTouchDiagnostics.log(
        "row=\(selectionID) session=\(String(describing: session)) event=button-action accepted=\(confirmed)"
      )
      guard confirmed else { return }
      selectionTouchState.confirmButtonAction()
    }
    props.onButtonPress()
  }

  @ViewBuilder
  private func navigationSelectionTracking<Content: View>(_ content: Content) -> some View {
    if let selectionID = listSelectionID {
      content.background(
        ListSelectionTouchTrackingView(
          selectionID: selectionID,
          selectionTarget: listSelectionTarget,
          isSelectionTargetCurrent: { target in
            listSelectionTarget(selectionID) === target
          },
          touchState: selectionTouchState,
          onTouchDown: { target in
            // Select the SwiftUI model during the cell recognizer's `.began`,
            // before the automatic Button style releases on touch-up.
            selectListItem(selectionID, target)
          },
          onTouchFinishedWithoutConfirmedPress: { session in
            clearListItem(selectionID, session)
          }
        )
      )
    } else {
      content
    }
  }

  private var listSelectionID: AnyHashable? {
    guard let listSelectionId = props.listSelectionId else {
      return nil
    }
    if let stringValue: String = listSelectionId.get() {
      return AnyHashable(stringValue)
    }
    if let doubleValue: Double = listSelectionId.get() {
      return AnyHashable(doubleValue)
    }
    return nil
  }
}

/// SwiftUI's iOS 26+ List cells do not contain UIControls for a `Button`; the
/// tap is implemented by gestures on the cell-hosting view. Observe that host
/// with a passive UIKit recognizer and select the real collection/table cell.
private struct ListSelectionTouchTrackingView: UIViewRepresentable {
  let selectionID: AnyHashable
  let selectionTarget: (AnyHashable) -> ListNavigationSelectionTarget?
  let isSelectionTargetCurrent: (ListNavigationSelectionTarget) -> Bool
  let touchState: ListSelectionTouchState
  let onTouchDown: (ListNavigationSelectionTarget?) -> Int?
  let onTouchFinishedWithoutConfirmedPress: (Int?) -> Bool

  func makeUIView(context: Context) -> ListSelectionTouchTrackingUIView {
    let view = ListSelectionTouchTrackingUIView()
    view.selectionID = selectionID
    view.selectionTarget = selectionTarget
    view.isSelectionTargetCurrent = isSelectionTargetCurrent
    view.touchState = touchState
    view.onTouchDown = onTouchDown
    view.onTouchFinishedWithoutConfirmedPress = onTouchFinishedWithoutConfirmedPress
    return view
  }

  func updateUIView(_ uiView: ListSelectionTouchTrackingUIView, context: Context) {
    uiView.selectionID = selectionID
    uiView.selectionTarget = selectionTarget
    uiView.isSelectionTargetCurrent = isSelectionTargetCurrent
    uiView.touchState = touchState
    uiView.onTouchDown = onTouchDown
    uiView.onTouchFinishedWithoutConfirmedPress = onTouchFinishedWithoutConfirmedPress
    uiView.attachToNearestCellIfNeeded()
  }
}

/// Bridges the SwiftUI Button action and the passive UIKit touch observer. The
/// recognizer sees `.ended` before SwiftUI is guaranteed to invoke the action,
/// so a time-based guess can momentarily clear a valid navigation selection.
private final class ListSelectionTouchState {
  private var currentSequence = 0
  private var confirmedSequence: Int?
  private var cancelledSequence: Int?

  func beginTouch() -> Int {
    currentSequence &+= 1
    confirmedSequence = nil
    cancelledSequence = nil
    // A Button action is only valid for the touch sequence which reached
    // `.ended`. If a new touch starts first, an action delivered late by
    // SwiftUI belongs to the old sequence and must not confirm the new native
    // selection session.
    buttonActionSequence = nil
    return currentSequence
  }

  private var sessionBySequence: [Int: Int] = [:]
  private var buttonActionSequence: Int?

  func setSession(_ session: Int?, for sequence: Int) {
    if let session {
      sessionBySequence[sequence] = session
    }
  }

  func markAwaitingButtonAction(_ sequence: Int) {
    guard canKeepSelection(for: sequence) else { return }
    buttonActionSequence = sequence
  }

  func session(for sequence: Int) -> Int? {
    sessionBySequence[sequence]
  }

  func sessionForButtonAction() -> Int? {
    guard let buttonActionSequence, canKeepSelection(for: buttonActionSequence) else { return nil }
    return sessionBySequence[buttonActionSequence]
  }

  func confirmButtonAction() {
    confirmedSequence = buttonActionSequence ?? currentSequence
  }

  func cancelTouch(_ sequence: Int) {
    guard currentSequence == sequence else { return }
    cancelledSequence = sequence
  }

  func isConfirmed(_ sequence: Int) -> Bool {
    confirmedSequence == sequence
  }

  func shouldKeepWaiting(for sequence: Int) -> Bool {
    canKeepSelection(for: sequence) && confirmedSequence != sequence
  }

  func canKeepSelection(for sequence: Int) -> Bool {
    currentSequence == sequence && cancelledSequence != sequence
  }
}

private final class ListSelectionTouchTrackingUIView: UIView {
  var selectionID: AnyHashable? {
    willSet {
      if selectionID != newValue {
        detachFromObservedCell()
        detachSelectionSource()
      }
    }
  }
  var selectionTarget: ((AnyHashable) -> ListNavigationSelectionTarget?)?
  var isSelectionTargetCurrent: ((ListNavigationSelectionTarget) -> Bool)?
  var touchState: ListSelectionTouchState?
  var onTouchDown: ((ListNavigationSelectionTarget?) -> Int?)?
  var onTouchFinishedWithoutConfirmedPress: ((Int?) -> Bool)?

  private weak var observedCell: UIView?
  private var touchObserver: ListSelectionTouchObserver?
  private var activeSelectionTarget: ListNavigationSelectionTarget?
  private var touchSequence = 0
  private var isTouchPrepared = false
  private var competingPanGestureRecognized = false
  private var registeredTransitionCleanupSequence: Int?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .clear
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      detachSelectionSource()
      detachFromObservedCell()
    } else {
      attachSelectionSource()
      attachToNearestCellIfNeeded()
    }
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    if superview == nil {
      detachSelectionSource()
      detachFromObservedCell()
    } else {
      attachSelectionSource()
      attachToNearestCellIfNeeded()
    }
  }

  deinit {
    detachSelectionSource()
    detachFromObservedCell()
  }

  private func attachSelectionSource() {
    guard let selectionID else { return }
    selectionTarget?(selectionID)?.attachSource(self)
  }

  private func detachSelectionSource() {
    activeSelectionTarget?.detachSource(self)
    guard let selectionID else { return }
    selectionTarget?(selectionID)?.detachSource(self)
  }

  func attachToNearestCellIfNeeded() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.attachSelectionSource()
      var candidate = self.superview
      var nearestCell: UIView?
      while let current = candidate {
        if current is UICollectionViewCell || current is UITableViewCell {
          nearestCell = current
          break
        }
        candidate = current.superview
      }

      guard let nearestCell else {
        self.detachFromObservedCell()
        return
      }
      guard self.observedCell !== nearestCell || self.touchObserver == nil else { return }

      // A SwiftUI List can move this representable between reused cells while
      // an interactive navigation transition is in flight. Never leave the
      // old passive recognizer attached: otherwise one physical touch is
      // delivered to both the old and new navigation item.
      self.detachFromObservedCell()
      let observer = ListSelectionTouchObserver(target: nil, action: nil)
      observer.onTouchEvent = { [weak self] observer, event in
        guard let self, self.touchObserver === observer else { return }
        self.handleCellTouch(observer, event: event)
      }
      observer.cancelsTouchesInView = false
      observer.delaysTouchesBegan = false
      observer.delaysTouchesEnded = false
      observer.delegate = self
      nearestCell.addGestureRecognizer(observer)
      self.observedCell = nearestCell
      self.touchObserver = observer
    }
  }

  private func detachFromObservedCell() {
    if let touchObserver {
      // Removing a recognizer need not deliver its target-action cancellation.
      // Only a still-held candidate is cancelled; a released Button action or
      // confirmed navigation keeps its existing selection/transition owner.
      touchObserver.invalidateTracking(reason: "detached")
      touchObserver.onTouchEvent = nil
      observedCell?.removeGestureRecognizer(touchObserver)
    }
    isTouchPrepared = false
    touchObserver = nil
    observedCell = nil
  }

  private func handleCellTouch(
    _ observer: ListSelectionTouchObserver, event: ListSelectionTouchObserver.TouchEvent
  ) {
    if event != .moved {
      ListSelectionTouchDiagnostics.log(
        "row=\(String(describing: selectionID)) sequence=\(touchSequence) event=\(event.rawValue) reason=\(observer.invalidationReason ?? "none")"
      )
    }
    switch event {
    case .began:
      // The delegate already reserved this session before UIKit arbitration.
      break
    case .moved:
      guard isTouchPrepared else { return }
      if !competingPanGestureRecognized,
        hasActiveCompetingPanGesture {
        competingPanGestureRecognized = true
        cancelPreparedTouch()
      }
    case .ended:
      guard isTouchPrepared else { return }
      let sequence = touchSequence
      guard canKeepSelection(for: sequence) else {
        cancelPreparedTouch()
        isTouchPrepared = false
        return
      }
      if competingPanGestureRecognized
        || hasActiveCompetingPanGesture
        || isTouchOutsideObservedCell(observer) {
        cancelPreparedTouch()
        return
      }
      isTouchPrepared = false
      touchState?.markAwaitingButtonAction(sequence)
      // SwiftUI may clear its pressed appearance after this recognizer receives
      // `.ended`. Reassert the real cell synchronously and at the end of this
      // main-loop turn so no display frame exposes the released state.
      activeSelectionTarget?.select()
      let target = activeSelectionTarget
      DispatchQueue.main.async { [weak self, weak target] in
        guard let self, let target, self.touchSequence == sequence,
          self.canKeepSelection(for: sequence),
          self.activeSelectionTarget === target else { return }
        target.select()
      }
      maintainSelectionUntilButtonAction(sequence: sequence)
    case .cancelled:
      cancelPreparedTouch()
    case .reset:
      cancelPreparedTouch()
      isTouchPrepared = false
      attachToNearestCellIfNeeded()
    }
  }

  private func cancelPreparedTouch() {
    guard isTouchPrepared else { return }
    // Keep the candidate until its terminal callback/reset. A competing pan
    // may acquire its transition coordinator after the first cancellation;
    // final cleanup must still be able to register with that coordinator.
    let sequence = touchSequence
    guard touchState?.isConfirmed(sequence) != true else { return }
    touchState?.cancelTouch(sequence)
    let shouldClear = onTouchFinishedWithoutConfirmedPress?(touchState?.session(for: sequence)) ?? true
    if shouldClear {
      let waitsForTransition = registerTransitionCompletionCleanup(sequence: sequence)
      deselectContainingListCell(keepingTarget: true)
      if !waitsForTransition {
        scheduleFinalCancelledTouchCleanup(sequence: sequence)
      }
    }
  }

  private func canKeepSelection(for sequence: Int) -> Bool {
    guard touchSequence == sequence,
      touchState?.canKeepSelection(for: sequence) == true else { return false }
    guard let target = activeSelectionTarget else { return true }
    return isSelectionTargetCurrent?(target) == true
  }

  /// `UIGestureRecognizer.state == .began` is too late when a touch starts on
  /// a source List while its native-stack pop is still finishing: the new push
  /// can cancel that pop first, and UIKit restores the old row selection. The
  /// recognizer delegate receives this callback as the touch enters the cell,
  /// so establish the new session before that transition arbitration.
  private func prepareTouchIfNeeded() {
    guard !isTouchPrepared else { return }
    isTouchPrepared = true
    touchSequence = touchState?.beginTouch() ?? touchSequence &+ 1
    competingPanGestureRecognized = false
    registeredTransitionCleanupSequence = nil
    let target = selectContainingListCell()
    activeSelectionTarget = target
    let session = onTouchDown?(target)
    touchState?.setSession(session, for: touchSequence)
    ListSelectionTouchDiagnostics.log(
      "row=\(String(describing: selectionID)) sequence=\(touchSequence) session=\(String(describing: session)) event=prepared"
    )
  }

  /// Keep UIKit's row state authoritative until SwiftUI actually invokes the
  /// Button action. In particular, do not use a short fixed timeout here: a
  /// late action can otherwise clear and then recreate selection during the
  /// first frame of a native-stack push.
  private func maintainSelectionUntilButtonAction(sequence: Int, framesRemaining: Int = 60) {
    guard canKeepSelection(for: sequence) else { return }
    if touchState?.isConfirmed(sequence) == true {
      activeSelectionTarget?.select()
      return
    }
    guard touchState?.shouldKeepWaiting(for: sequence) ?? false else { return }
    guard framesRemaining > 0 else {
      touchState?.cancelTouch(sequence)
      let shouldClear = onTouchFinishedWithoutConfirmedPress?(touchState?.session(for: sequence)) ?? true
      if shouldClear {
        deselectContainingListCell()
      }
      return
    }
    activeSelectionTarget?.select()
    DispatchQueue.main.asyncAfter(deadline: .now() + (1.0 / 60.0)) { [weak self] in
      self?.maintainSelectionUntilButtonAction(
        sequence: sequence,
        framesRemaining: framesRemaining - 1
      )
    }
  }

  /// A passive recognizer receives its cancellation before UIKit finishes an
  /// interactive navigation transition. UIKit may restore the touched cell as
  /// part of a cancelled transition, so perform the authoritative deselection
  /// after the coordinator completion instead of relying on movement distance.
  @discardableResult
  private func registerTransitionCompletionCleanup(sequence: Int) -> Bool {
    if registeredTransitionCleanupSequence == sequence {
      return true
    }
    guard let coordinator = activeViewControllerTransitionCoordinator else {
      return false
    }
    registeredTransitionCleanupSequence = sequence
    coordinator.animate(alongsideTransition: nil) { [weak self] _ in
      // UIKit/SwiftUI restore the source hierarchy just after the coordinator
      // completion when an interactive pop is cancelled. Clear both the List
      // binding and its concrete cell after that restoration has committed.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        guard let self, self.touchSequence == sequence else { return }
        let shouldClear = self.onTouchFinishedWithoutConfirmedPress?(
          self.touchState?.session(for: sequence)
        ) ?? true
        if shouldClear {
          self.deselectContainingListCell()
        }
        self.registeredTransitionCleanupSequence = nil
      }
    }
    return true
  }

  /// Non-navigation Button cancellation still needs one final main-loop pass:
  /// SwiftUI applies its released/cancelled state after sibling recognizers.
  private func scheduleFinalCancelledTouchCleanup(sequence: Int) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.touchSequence == sequence else { return }
      let shouldClear = self.onTouchFinishedWithoutConfirmedPress?(
        self.touchState?.session(for: sequence)
      ) ?? true
      if shouldClear {
        self.deselectContainingListCell()
      }
    }
  }

  private func isTouchOutsideObservedCell(_ observer: ListSelectionTouchObserver) -> Bool {
    guard let observedCell, let touch = observer.primaryTouch else { return true }
    return !observedCell.bounds.contains(touch.location(in: observedCell))
  }

  /// Follow UIKit's own gesture arbitration instead of applying a custom
  /// movement threshold. Once a system pan begins, the Button press is cancelled.
  private var hasActiveCompetingPanGesture: Bool {
    var candidate = observedCell?.superview
    while let current = candidate {
      for recognizer in current.gestureRecognizers ?? [] {
        guard recognizer !== touchObserver,
          recognizer is UIPanGestureRecognizer else {
          continue
        }
        if recognizer.state == .began || recognizer.state == .changed {
          return true
        }
      }
      candidate = current.superview
    }
    return false
  }

  private var activeViewControllerTransitionCoordinator: UIViewControllerTransitionCoordinator? {
    var responder: UIResponder? = observedCell
    var inspectedViewControllers = Set<ObjectIdentifier>()
    while let current = responder {
      if let viewController = current as? UIViewController {
        var candidate: UIViewController? = viewController
        while let controller = candidate,
          inspectedViewControllers.insert(ObjectIdentifier(controller)).inserted {
          if let coordinator = controller.transitionCoordinator,
            coordinator.isAnimated || coordinator.isInteractive {
            return coordinator
          }
          if let coordinator = controller.navigationController?.transitionCoordinator,
            coordinator.isAnimated || coordinator.isInteractive {
            return coordinator
          }
          candidate = controller.parent
        }
      }
      responder = current.next
    }
    return nil
  }

  private func selectContainingListCell() -> ListNavigationSelectionTarget? {
    guard let observedCell else { return nil }
    var candidate: UIView? = observedCell
    var tableCell: UITableViewCell?
    var collectionCell: UICollectionViewCell?
    var tableView: UITableView?
    var collectionView: UICollectionView?

    while let current = candidate {
      if tableCell == nil, let cell = current as? UITableViewCell {
        tableCell = cell
      }
      if collectionCell == nil, let cell = current as? UICollectionViewCell {
        collectionCell = cell
      }
      if tableView == nil, let view = current as? UITableView {
        tableView = view
      }
      if collectionView == nil, let view = current as? UICollectionView {
        collectionView = view
      }
      candidate = current.superview
    }

    if let tableView, let tableCell, let indexPath = tableView.indexPath(for: tableCell) {
      let target = ListNavigationSelectionTarget(tableView: tableView, indexPath: indexPath, sourceView: self)
      if !tableView.delaysContentTouches {
        target.select(highlighted: true)
      }
      return target
    } else if let collectionView, let collectionCell,
      let indexPath = collectionView.indexPath(for: collectionCell) {
      let target = ListNavigationSelectionTarget(
        collectionView: collectionView,
        indexPath: indexPath,
        sourceView: self
      )
      if !collectionView.delaysContentTouches {
        target.select(highlighted: true)
      }
      return target
    }
    return nil
  }

  private func deselectContainingListCell(keepingTarget: Bool = false) {
    activeSelectionTarget?.deselect(animated: false)
    if !keepingTarget {
      activeSelectionTarget = nil
    }
  }

}

/// Receives raw touches synchronously and never participates in gesture
/// prevention, so it cannot block the native-stack back pan gesture.
private final class ListSelectionTouchObserver: UIGestureRecognizer {
  enum TouchEvent: String {
    case began, moved, ended, cancelled, reset
  }

  var onTouchEvent: ((ListSelectionTouchObserver, TouchEvent) -> Void)?
  private(set) var primaryTouch: UITouch?
  private(set) var invalidationReason: String?
  private var trackedTouches: [ObjectIdentifier: UITouch] = [:]
  private var didFinishPrimaryTouch = false
  private var isInteractionInvalidated = false
  private var lifecycleObserver: CFRunLoopObserver?

  /// Reserve the physical touch before UIKit arbitrates an in-flight pop.
  /// An overlapping finger cancels this candidate, but all fingers continue
  /// to be tracked until they leave; none may restart the same interaction.
  func receive(_ touch: UITouch) -> Bool {
    let identifier = ObjectIdentifier(touch)
    guard trackedTouches[identifier] == nil else { return false }
    trackedTouches[identifier] = touch
    if primaryTouch != nil {
      invalidateInteraction(reason: "additional-touch")
      return false
    }
    primaryTouch = touch
    observeTouchLifecycle()
    return true
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    guard !trackedTouches.isEmpty else { return }
    if state == .possible { state = .began }
    onTouchEvent?(self, .began)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesMoved(touches, with: event)
    guard state == .began || state == .changed else { return }
    state = .changed
    if !isInteractionInvalidated { onTouchEvent?(self, .moved) }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesEnded(touches, with: event)
    if let primaryTouch, touches.contains(primaryTouch), !didFinishPrimaryTouch {
      didFinishPrimaryTouch = true
      // Deliver the physical end directly, before setting the recognizer's
      // terminal state can cause SwiftUI to dispatch its Button action.
      if !isInteractionInvalidated { onTouchEvent?(self, .ended) }
    }
    removeTouches(touches)
    finishObservationIfEmpty()
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesCancelled(touches, with: event)
    invalidateInteraction(reason: "touches-cancelled")
    removeTouches(touches)
    finishObservationIfEmpty()
  }

  override func reset() {
    // `.failed` does not send target-action. Also handle delegate-only
    // candidates for which UIKit never delivered a matching touchesBegan.
    invalidateInteraction(reason: "reset-before-end")
    stopObservingTouchLifecycle()
    trackedTouches.removeAll()
    onTouchEvent?(self, .reset)
    primaryTouch = nil
    didFinishPrimaryTouch = false
    isInteractionInvalidated = false
    invalidationReason = nil
    super.reset()
  }

  func invalidateTracking(reason: String) {
    invalidateInteraction(reason: reason)
    stopObservingTouchLifecycle()
    trackedTouches.removeAll()
    if !didFinishPrimaryTouch { finishObservationIfEmpty() }
  }

  private func invalidateInteraction(reason: String) {
    guard primaryTouch != nil, !didFinishPrimaryTouch, !isInteractionInvalidated else { return }
    isInteractionInvalidated = true
    invalidationReason = reason
    onTouchEvent?(self, .cancelled)
  }

  private func removeTouches(_ touches: Set<UITouch>) {
    for touch in touches { trackedTouches.removeValue(forKey: ObjectIdentifier(touch)) }
  }

  private func finishObservationIfEmpty() {
    guard primaryTouch != nil, trackedTouches.isEmpty else { return }
    stopObservingTouchLifecycle()
    guard state == .possible || state == .began || state == .changed else { return }
    if isInteractionInvalidated {
      state = state == .possible ? .failed : .cancelled
    } else {
      state = .ended
    }
  }

  /// A system menu can consume a terminal callback or detach the observer.
  /// Check the actual UITouch phase when the main run loop is about to sleep;
  /// this never wakes/polls the run loop and imposes no limit on a held touch.
  private func observeTouchLifecycle() {
    guard lifecycleObserver == nil else { return }
    let observer = CFRunLoopObserverCreateWithHandler(
      nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0
    ) { [weak self] _, _ in
      self?.reconcileTouchLifecycle()
    }
    lifecycleObserver = observer
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
  }

  private func reconcileTouchLifecycle() {
    guard view?.window != nil else {
      invalidateTracking(reason: "observed-view-unavailable")
      return
    }
    let finishedTouches = Set(trackedTouches.values.filter {
      $0.phase == .ended || $0.phase == .cancelled
    })
    guard !finishedTouches.isEmpty else { return }
    // A phase change without the corresponding raw callback is cancellation,
    // not permission to synthesize a click through a system menu.
    invalidateInteraction(reason: "missing-terminal-callback")
    removeTouches(finishedTouches)
    finishObservationIfEmpty()
  }

  private func stopObservingTouchLifecycle() {
    if let lifecycleObserver { CFRunLoopObserverInvalidate(lifecycleObserver) }
    lifecycleObserver = nil
  }

  deinit {
    stopObservingTouchLifecycle()
  }

  override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

  override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

extension ListSelectionTouchTrackingUIView: UIGestureRecognizerDelegate {
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    if let observer = gestureRecognizer as? ListSelectionTouchObserver,
      observer === touchObserver, observer.receive(touch) {
      prepareTouchIfNeeded()
      ListSelectionTouchDiagnostics.log(
        "row=\(String(describing: selectionID)) sequence=\(touchSequence) event=received touch=\(ObjectIdentifier(touch))"
      )
    }
    return true
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    true
  }
}

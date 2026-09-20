// Copyright 2025-present 650 Industries. All rights reserved.

import SwiftUI
import UIKit
import ExpoModulesCore

public struct Button: ExpoSwiftUI.View {
  @ObservedObject public var props: ButtonProps
  @Environment(\.expoListSelectionAction) private var selectListItem
  @Environment(\.expoListSelectionClearAction) private var clearListItem
  @Environment(\.expoListSelectionConfirmAction) private var confirmListItem
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
      let confirmed = confirmListItem(selectionID)
      guard confirmed else { return }
      selectionTouchState.confirmCurrentTouch()
    }
    props.onButtonPress()
  }

  @ViewBuilder
  private func navigationSelectionTracking<Content: View>(_ content: Content) -> some View {
    if let selectionID = listSelectionID {
      content.background(
        ListSelectionTouchTrackingView(
          touchState: selectionTouchState,
          onTouchDown: { target in
            // Select the SwiftUI model during the cell recognizer's `.began`,
            // before the automatic Button style releases on touch-up.
            selectListItem(selectionID, target)
          },
          onTouchFinishedWithoutConfirmedPress: {
            clearListItem(selectionID)
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
  let touchState: ListSelectionTouchState
  let onTouchDown: (ListNavigationSelectionTarget?) -> Void
  let onTouchFinishedWithoutConfirmedPress: () -> Bool

  func makeUIView(context: Context) -> ListSelectionTouchTrackingUIView {
    let view = ListSelectionTouchTrackingUIView()
    view.touchState = touchState
    view.onTouchDown = onTouchDown
    view.onTouchFinishedWithoutConfirmedPress = onTouchFinishedWithoutConfirmedPress
    return view
  }

  func updateUIView(_ uiView: ListSelectionTouchTrackingUIView, context: Context) {
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
    return currentSequence
  }

  func confirmCurrentTouch() {
    confirmedSequence = currentSequence
  }

  func cancelTouch(_ sequence: Int) {
    guard currentSequence == sequence else { return }
    cancelledSequence = sequence
  }

  func isConfirmed(_ sequence: Int) -> Bool {
    confirmedSequence == sequence
  }

  func shouldKeepWaiting(for sequence: Int) -> Bool {
    currentSequence == sequence && cancelledSequence != sequence && confirmedSequence != sequence
  }
}

private final class ListSelectionTouchTrackingUIView: UIView {
  var touchState: ListSelectionTouchState?
  var onTouchDown: ((ListNavigationSelectionTarget?) -> Void)?
  var onTouchFinishedWithoutConfirmedPress: (() -> Bool)?

  private weak var observedCell: UIView?
  private var touchObserver: ListSelectionTouchObserver?
  private weak var selectedTableView: UITableView?
  private weak var selectedTableCell: UITableViewCell?
  private weak var selectedCollectionView: UICollectionView?
  private weak var selectedCollectionCell: UICollectionViewCell?
  private var activeSelectionTarget: ListNavigationSelectionTarget?
  private var touchSequence = 0
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
    attachToNearestCellIfNeeded()
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    attachToNearestCellIfNeeded()
  }

  deinit {
    detachFromObservedCell()
  }

  func attachToNearestCellIfNeeded() {
    guard observedCell == nil else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.observedCell == nil else { return }
      var candidate = self.superview
      while let current = candidate {
        if current is UICollectionViewCell || current is UITableViewCell {
          let observer = ListSelectionTouchObserver(
            target: self,
            action: #selector(self.handleCellTouch)
          )
          observer.cancelsTouchesInView = false
          observer.delaysTouchesBegan = false
          observer.delaysTouchesEnded = false
          observer.delegate = self
          current.addGestureRecognizer(observer)
          self.observedCell = current
          self.touchObserver = observer
          return
        }
        candidate = current.superview
      }
    }
  }

  private func detachFromObservedCell() {
    if let touchObserver {
      observedCell?.removeGestureRecognizer(touchObserver)
    }
    touchObserver = nil
    observedCell = nil
  }

  @objc private func handleCellTouch(_ recognizer: UIGestureRecognizer) {
    switch recognizer.state {
    case .began:
      touchSequence = touchState?.beginTouch() ?? touchSequence &+ 1
      competingPanGestureRecognized = false
      registeredTransitionCleanupSequence = nil
      let target = selectContainingListCell()
      activeSelectionTarget = target
      onTouchDown?(target)
    case .changed:
      if !competingPanGestureRecognized,
        hasActiveCompetingPanGesture || hasInteractiveViewControllerTransition {
        competingPanGestureRecognized = true
        touchState?.cancelTouch(touchSequence)
        _ = onTouchFinishedWithoutConfirmedPress?()
        // An interactive navigation cancellation can restore the cell after
        // this callback. Keep the target until the transition has completely
        // finished, then clear it once more after UIKit's own bookkeeping.
        deselectContainingListCell(keepingTarget: true)
        registerTransitionCompletionCleanup(sequence: touchSequence)
      }
    case .ended:
      let sequence = touchSequence
      if competingPanGestureRecognized
        || hasInteractiveViewControllerTransition
        || isTouchOutsideObservedCell(recognizer) {
        touchState?.cancelTouch(sequence)
        _ = onTouchFinishedWithoutConfirmedPress?()
        let waitsForTransition = registerTransitionCompletionCleanup(sequence: sequence)
        deselectContainingListCell(keepingTarget: true)
        if !waitsForTransition {
          scheduleFinalCancelledTouchCleanup(sequence: sequence)
        }
        return
      }
      // SwiftUI may clear its pressed appearance after this recognizer receives
      // `.ended`. Reassert the real cell synchronously and at the end of this
      // main-loop turn so no display frame exposes the released state.
      activeSelectionTarget?.select()
      DispatchQueue.main.async { [weak self] in
        guard let self, self.touchSequence == sequence else { return }
        self.activeSelectionTarget?.select()
      }
      maintainSelectionUntilButtonAction(sequence: sequence)
    case .cancelled, .failed:
      let sequence = touchSequence
      touchState?.cancelTouch(sequence)
      _ = onTouchFinishedWithoutConfirmedPress?()
      let waitsForTransition = registerTransitionCompletionCleanup(sequence: sequence)
      deselectContainingListCell(keepingTarget: true)
      if !waitsForTransition {
        scheduleFinalCancelledTouchCleanup(sequence: sequence)
      }
    default:
      break
    }
  }

  /// Keep UIKit's row state authoritative until SwiftUI actually invokes the
  /// Button action. In particular, do not use a short fixed timeout here: a
  /// late action can otherwise clear and then recreate selection during the
  /// first frame of a native-stack push.
  private func maintainSelectionUntilButtonAction(sequence: Int, framesRemaining: Int = 60) {
    guard touchSequence == sequence else { return }
    if touchState?.isConfirmed(sequence) == true {
      activeSelectionTarget?.select()
      return
    }
    guard touchState?.shouldKeepWaiting(for: sequence) ?? false else { return }
    guard framesRemaining > 0 else {
      touchState?.cancelTouch(sequence)
      _ = onTouchFinishedWithoutConfirmedPress?()
      deselectContainingListCell()
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
        _ = self.onTouchFinishedWithoutConfirmedPress?()
        self.deselectContainingListCell()
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
      self.deselectContainingListCell()
    }
  }

  private func isTouchOutsideObservedCell(_ recognizer: UIGestureRecognizer) -> Bool {
    guard let observedCell else { return true }
    return !observedCell.bounds.contains(recognizer.location(in: observedCell))
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

  private var hasInteractiveViewControllerTransition: Bool {
    activeViewControllerTransitionCoordinator?.isInteractive == true
  }

  private var activeViewControllerTransitionCoordinator: UIViewControllerTransitionCoordinator? {
    var responder: UIResponder? = observedCell
    while let current = responder {
      if let viewController = current as? UIViewController {
        if let coordinator = viewController.transitionCoordinator, coordinator.isAnimated {
          return coordinator
        }
        if let coordinator = viewController.navigationController?.transitionCoordinator,
          coordinator.isAnimated {
          return coordinator
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
      tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
      selectedTableView = tableView
      selectedTableCell = tableCell
      let target = ListNavigationSelectionTarget(tableView: tableView, indexPath: indexPath)
      target.select()
      return target
    } else if let collectionView, let collectionCell,
      let indexPath = collectionView.indexPath(for: collectionCell) {
      collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
      selectedCollectionView = collectionView
      selectedCollectionCell = collectionCell
      let target = ListNavigationSelectionTarget(
        collectionView: collectionView,
        indexPath: indexPath
      )
      target.select()
      return target
    }
    return nil
  }

  private func deselectContainingListCell(keepingTarget: Bool = false) {
    activeSelectionTarget?.deselect(animated: false)
    if let tableView = selectedTableView, let cell = selectedTableCell,
      let indexPath = tableView.indexPath(for: cell) {
      cell.isHighlighted = false
      if tableView.indexPathForSelectedRow == indexPath {
        tableView.deselectRow(at: indexPath, animated: false)
      }
      cell.isSelected = false
    }
    if let collectionView = selectedCollectionView, let cell = selectedCollectionCell,
      let indexPath = collectionView.indexPath(for: cell) {
      cell.isHighlighted = false
      if collectionView.indexPathsForSelectedItems?.contains(indexPath) == true {
        collectionView.deselectItem(at: indexPath, animated: false)
      }
      cell.isSelected = false
    }
    if !keepingTarget {
      selectedTableView = nil
      selectedTableCell = nil
      selectedCollectionView = nil
      selectedCollectionCell = nil
      activeSelectionTarget = nil
    }
  }

}

/// Receives raw touches synchronously and never participates in gesture
/// prevention, so it cannot block the native-stack back pan gesture.
private final class ListSelectionTouchObserver: UIGestureRecognizer {
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    guard state == .possible else { return }
    state = .began
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesMoved(touches, with: event)
    guard state == .began || state == .changed else { return }
    state = .changed
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesEnded(touches, with: event)
    guard state == .began || state == .changed else { return }
    state = .ended
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesCancelled(touches, with: event)
    if state == .began || state == .changed {
      state = .cancelled
    }
  }

  override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

  override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

extension ListSelectionTouchTrackingUIView: UIGestureRecognizerDelegate {
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    true
  }
}

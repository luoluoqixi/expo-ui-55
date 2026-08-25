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
  var onSelectionChange = EventDispatcher()
}

private final class ListScrollPositionStore {
  weak var scrollView: UIScrollView?
  var hasObservedScrollView = false
  var offset: CGPoint?
}
struct ListView: ExpoSwiftUI.View {
  @ObservedObject var props: ListProps
  @State private var selection = Set<AnyHashable>()
  @State private var hasScrolledToInitialTarget = false

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
      }
      .background {
        ScrollInsetAdjustmentView(
          automaticallyAdjustsScrollIndicatorInsets: props.automaticallyAdjustsScrollIndicatorInsets ?? true,
          contentInsetAdjustmentBehavior: props.contentInsetAdjustmentBehavior,
          correctsNestedScrollIndicatorFrame: props.correctsNestedScrollIndicatorFrame,
          dismissKeyboardOnTap: props.dismissKeyboardOnTap,
          onRefresh: {
            props.onRefresh(["refreshing": true])
          },
          refreshEnabled: props.refreshEnabled,
          refreshable: props.refreshable,
          refreshing: props.refreshing,
          scrollPositionRestoreToken: props.scrollPositionRestoreToken,
          scrollPositionStore: props.scrollPositionStore,
          tracksNavigationBarScrollEdge: props.tracksNavigationBarScrollEdge
        )
      }
      .onAppear {
        selection = Self.getHashableSetFromEither(props.selection)
        scrollToInitialTarget(proxy)
      }
      .onChange(of: props.selection) { newValue in
        selection = Self.getHashableSetFromEither(newValue)
      }
      .onChange(of: props.initialScrollTarget) { _ in
        hasScrolledToInitialTarget = false
        scrollToInitialTarget(proxy)
      }
      .onChange(of: selection) { newSelection in
        handleSelectionChange(selection: newSelection)
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
  let contentInsetAdjustmentBehavior: ListContentInsetAdjustmentBehavior?
  let correctsNestedScrollIndicatorFrame: Bool
  let dismissKeyboardOnTap: Bool
  let onRefresh: () -> Void
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
    view.contentInsetAdjustmentBehavior = contentInsetAdjustmentBehavior
    view.correctsNestedScrollIndicatorFrame = correctsNestedScrollIndicatorFrame
    view.dismissKeyboardOnTap = dismissKeyboardOnTap
    view.onRefresh = onRefresh
    view.refreshEnabled = refreshEnabled
    view.refreshable = refreshable
    view.refreshing = refreshing
    view.scrollPositionRestoreToken = scrollPositionRestoreToken
    view.scrollPositionStore = scrollPositionStore
    view.tracksNavigationBarScrollEdge = tracksNavigationBarScrollEdge
    return viewController
  }

  func updateUIViewController(_ uiViewController: ScrollInsetAdjustmentViewController, context: Context) {
    let view = uiViewController.adjustmentView
    view.automaticallyAdjustsScrollIndicatorInsets = automaticallyAdjustsScrollIndicatorInsets
    view.contentInsetAdjustmentBehavior = contentInsetAdjustmentBehavior
    view.correctsNestedScrollIndicatorFrame = correctsNestedScrollIndicatorFrame
    view.dismissKeyboardOnTap = dismissKeyboardOnTap
    view.onRefresh = onRefresh
    view.refreshEnabled = refreshEnabled
    view.refreshable = refreshable
    view.refreshing = refreshing
    view.scrollPositionRestoreToken = scrollPositionRestoreToken
    view.scrollPositionStore = scrollPositionStore
    view.tracksNavigationBarScrollEdge = tracksNavigationBarScrollEdge
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
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
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
    tracksNavigationBarScrollEdge &&
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

    var touchedView = touch.view
    while let currentView = touchedView {
      if currentView is UITextField || currentView is UITextView {
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

// Extract production Swift state/observer code; UIKit doubles only supply
// physical touch phases and recognizer storage. This is not a device UI test.
// Run: node --test tests/native_list_touch.test.cjs (macOS / Swift).
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { mkdtempSync, readFileSync, rmSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { after, before, test } = require('node:test');

const source = readFileSync(join(__dirname, '../ios/Button/Button.swift'), 'utf8');
let directory;
let executable;

function extractBlock(marker, input = source) {
  const start = input.indexOf(marker);
  assert.ok(start >= 0, `Missing ${marker}`);
  let end = input.indexOf('{', start) + 1;
  let depth = 1;
  while (depth > 0 && end < input.length) {
    if (input[end] === '{') depth += 1;
    if (input[end] === '}') depth -= 1;
    end += 1;
  }
  assert.equal(depth, 0);
  return input.slice(start, end);
}
const extractClass = (name, input) => extractBlock(`private final class ${name}`, input);
const viewSource = extractClass('ListSelectionTouchTrackingUIView');
const listSource = readFileSync(join(__dirname, '../ios/ListView.swift'), 'utf8');

before(() => {
  directory = mkdtempSync(join(tmpdir(), 'expo-ui-touch-regression-'));
  executable = join(directory, 'touch-regression');
  const swiftPath = join(directory, 'main.swift');
  writeFileSync(swiftPath, `
import Foundation
import CoreFoundation

final class UIView { var window: NSObject? = NSObject() }
final class UIEvent {}
final class UITouch: NSObject {
  enum Phase { case began, moved, stationary, ended, cancelled }
  var phase: Phase = .began
}
class UIGestureRecognizer {
  enum State { case possible, began, changed, ended, cancelled, failed }
  var state: State = .possible
  var view: UIView? = UIView()
  init(target: AnyObject?, action: Any?) {}
  func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {}
  func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {}
  func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {}
  func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {}
  func reset() { state = .possible }
  func canPrevent(_ other: UIGestureRecognizer) -> Bool { true }
  func canBePrevented(by other: UIGestureRecognizer) -> Bool { true }
}

${extractClass('ListSelectionTouchState')}
${extractClass('ListSelectionTouchObserver')}
${extractClass('ListSelectionInteractionState', listSource)}

private enum ListSelectionTouchDiagnostics {
  static func log(_ message: @autoclosure () -> String) {}
}
private final class ListNavigationSelectionTarget {
  var selected = false
  var highlighted = false
  func select(highlighted: Bool = false) { selected = true; self.highlighted = highlighted }
  func deselect(animated: Bool) { selected = false; highlighted = false }
  func matches(_ other: ListNavigationSelectionTarget?) -> Bool { self === other }
  func finishDeselectBackgroundAnimation() -> Int { 0 }
}
private final class Props {
  var pressCount = 0
  func onButtonPress() { pressCount += 1 }
}

// Run the actual production handlers together, including queued reselection.
private final class RowHarness {
  var selectionID: AnyHashable?
  var touchState: ListSelectionTouchState? = ListSelectionTouchState()
  var activeSelectionTarget: ListNavigationSelectionTarget?
  var touchSequence = 0
  var isTouchPrepared = false
  var competingPanGestureRecognized = false
  var registeredTransitionCleanupSequence: Int?
  var transitionAvailable = false
  var hasActiveCompetingPanGesture = false
  var outside = false
  var onTouchDown: ((ListNavigationSelectionTarget?) -> Int?)?
  var onTouchFinishedWithoutConfirmedPress: ((Int?) -> Bool)?
  var isSelectionTargetCurrent: ((ListNavigationSelectionTarget) -> Bool)?
  let observer = ListSelectionTouchObserver(target: nil, action: nil)
  let interaction: ListSelectionInteractionState
  let delaysContentTouches: Bool
  let props = Props()
  var listSelectionID: AnyHashable? { selectionID }
  var selectionTouchState: ListSelectionTouchState { touchState! }
  var confirmListItem: (AnyHashable, Int?) -> Bool {
    { [interaction] in interaction.confirm($0, session: $1) }
  }

  init(_ id: String, delays: Bool, interaction: ListSelectionInteractionState) {
    selectionID = AnyHashable(id)
    delaysContentTouches = delays
    self.interaction = interaction
    onTouchDown = { interaction.begin(AnyHashable(id), target: $0) }
    onTouchFinishedWithoutConfirmedPress = { interaction.shouldClearUnconfirmedSelection(AnyHashable(id), session: $0) }
    isSelectionTargetCurrent = { interaction.navigationTarget(for: AnyHashable(id)) === $0 }
    observer.onTouchEvent = { [weak self] observer, event in self?.handleCellTouch(observer, event: event) }
  }
  func receive(_ touch: UITouch) { if observer.receive(touch) { prepareTouchIfNeeded() } }
  func click() { handlePress() }
  private func selectContainingListCell() -> ListNavigationSelectionTarget? {
    let target = ListNavigationSelectionTarget()
    if !delaysContentTouches { target.select(highlighted: true) }
    return target
  }
  private func isTouchOutsideObservedCell(_ observer: ListSelectionTouchObserver) -> Bool { outside }
  private func registerTransitionCompletionCleanup(sequence: Int) -> Bool {
    if transitionAvailable { registeredTransitionCleanupSequence = sequence }
    return transitionAvailable
  }
  private func attachToNearestCellIfNeeded() {}
  ${extractBlock('  private func handlePress()')}
  ${extractBlock('  private func handleCellTouch(', viewSource)}
  ${extractBlock('  private func cancelPreparedTouch()', viewSource)}
  ${extractBlock('  private func canKeepSelection(for', viewSource)}
  ${extractBlock('  private func prepareTouchIfNeeded()', viewSource)}
  ${extractBlock('  private func maintainSelectionUntilButtonAction(', viewSource)}
  ${extractBlock('  private func scheduleFinalCancelledTouchCleanup(', viewSource)}
  ${extractBlock('  private func deselectContainingListCell(', viewSource)}
}

private final class Events { var values: [String] = [] }
private func makeObserver() -> (ListSelectionTouchObserver, Events) {
  let observer = ListSelectionTouchObserver(target: nil, action: nil)
  let events = Events()
  observer.onTouchEvent = { observer, event in
    events.values.append(event == .cancelled
      ? "cancelled:" + (observer.invalidationReason ?? "none") : event.rawValue)
  }
  return (observer, events)
}

private func spin(_ duration: TimeInterval = 0.03) {
  let timer = Timer(timeInterval: duration, repeats: false) { _ in }
  RunLoop.main.add(timer, forMode: .common)
  RunLoop.main.run(until: Date().addingTimeInterval(duration))
  timer.invalidate()
}

private func run(_ scenario: String) {
  let (observer, events) = makeObserver()
  let first = UITouch()
  let event = UIEvent()
  precondition(observer.receive(first))

  switch scenario {
  case "long-hold":
    observer.touchesBegan([first], with: event)
    first.phase = .stationary
    spin(1.15)
    precondition(events.values == ["began"], "A held finger must not time out")
    first.phase = .ended
    observer.touchesEnded([first], with: event)
    observer.reset()
    precondition(events.values == ["began", "ended", "reset"])

  case "delegate-only-reset":
    let idle = ListSelectionTouchObserver(target: nil, action: nil)
    idle.invalidateTracking(reason: "detached-before-touch")
    precondition(idle.state == .possible, "An unused observer must not synthesize a gesture")
    observer.reset()
    precondition(events.values == ["cancelled:reset-before-end", "reset"])

  case "missing-terminal", "missing-cancel", "delegate-only-terminal":
    if scenario != "delegate-only-terminal" { observer.touchesBegan([first], with: event) }
    first.phase = scenario == "missing-cancel" ? .cancelled : .ended
    spin()
    precondition(events.values.last == "cancelled:missing-terminal-callback")
    precondition(!events.values.contains("ended"), "A lost callback cannot synthesize a click")
    observer.reset()
    precondition(events.values.filter { $0.hasPrefix("cancelled:") }.count == 1)

  case "cancelled":
    observer.touchesBegan([first], with: event)
    first.phase = .cancelled
    observer.touchesCancelled([first], with: event)
    observer.reset()
    precondition(events.values == ["began", "cancelled:touches-cancelled", "reset"])

  case "detach-held", "detach-released":
    observer.touchesBegan([first], with: event)
    if scenario == "detach-released" {
      first.phase = .ended
      observer.touchesEnded([first], with: event)
    }
    observer.invalidateTracking(reason: "detached")
    observer.reset()
    precondition(events.values == (scenario == "detach-held"
      ? ["began", "cancelled:detached", "reset"] : ["began", "ended", "reset"]))

  case "view-disappeared":
    observer.touchesBegan([first], with: event)
    observer.view?.window = nil
    spin()
    precondition(events.values == ["began", "cancelled:observed-view-unavailable"])

  case "overlapping-fingers":
    observer.touchesBegan([first], with: event)
    precondition(!observer.receive(first), "The same finger is not a new interaction")
    let second = UITouch()
    precondition(!observer.receive(second))
    observer.touchesBegan([second], with: event)
    precondition(observer.primaryTouch === first)
    second.phase = .ended
    observer.touchesEnded([second], with: event)
    precondition(observer.state != .ended, "The second finger cannot end the first")
    let third = UITouch()
    precondition(!observer.receive(third), "Repeated taps cannot replace a held primary finger")
    observer.touchesBegan([third], with: event)
    observer.touchesMoved([first], with: event)
    first.phase = .ended
    observer.touchesEnded([first], with: event)
    precondition(observer.state != .ended)
    let fourth = UITouch()
    precondition(!observer.receive(fourth), "Keep tracking new fingers after the primary has lifted")
    observer.touchesBegan([fourth], with: event)
    third.phase = .ended
    observer.touchesEnded([third], with: event)
    precondition(observer.state != .cancelled, "Do not reset while another tracked finger remains")
    fourth.phase = .ended
    observer.touchesEnded([fourth], with: event)
    precondition(observer.state == .cancelled)
    precondition(events.values.filter { $0.hasPrefix("cancelled:") } == ["cancelled:additional-touch"])
    precondition(!events.values.contains("ended") && !events.values.contains("moved"))
    observer.reset()
    events.values.removeAll()
    let next = UITouch()
    precondition(observer.receive(next), "A fresh touch works once every finger has left")
    observer.touchesBegan([next], with: event)
    next.phase = .ended
    observer.touchesEnded([next], with: event)
    precondition(events.values == ["began", "ended"])

  case "session-cancellation":
    let state = ListSelectionTouchState()
    let old = state.beginTouch()
    state.setSession(41, for: old)
    state.markAwaitingButtonAction(old)
    precondition(state.sessionForButtonAction() == 41)
    state.cancelTouch(old)
    state.markAwaitingButtonAction(old)
    precondition(state.sessionForButtonAction() == nil)
    precondition(!state.canKeepSelection(for: old))
    let current = state.beginTouch()
    state.setSession(42, for: current)
    state.markAwaitingButtonAction(old)
    state.cancelTouch(old)
    precondition(state.sessionForButtonAction() == nil)
    precondition(!state.canKeepSelection(for: old) && state.canKeepSelection(for: current))
    state.markAwaitingButtonAction(current)
    precondition(state.sessionForButtonAction() == 42)
    state.confirmButtonAction()
    precondition(state.isConfirmed(current) && !state.shouldKeepWaiting(for: current))

  case "row-long-hold", "row-menu-cancellation", "row-stale-reselect", "row-superseded", "row-detach-after-release", "row-late-pan-transition", "row-late-cancel-transition":
    for delays in [true, false] {
      let interaction = ListSelectionInteractionState()
      let row = RowHarness("first", delays: delays, interaction: interaction)
      let touch = UITouch()
      row.receive(touch)
      row.observer.touchesBegan([touch], with: event)
      let target = row.activeSelectionTarget!
      precondition(target.selected == !delays, "Respect delaysContentTouches at touch-down")
      if scenario == "row-late-pan-transition" || scenario == "row-late-cancel-transition" {
        if scenario == "row-late-pan-transition" {
          row.hasActiveCompetingPanGesture = true
          row.observer.touchesMoved([touch], with: event)
        } else {
          touch.phase = .cancelled
          row.observer.touchesCancelled([touch], with: event)
        }
        precondition(row.registeredTransitionCleanupSequence == nil)
        row.transitionAvailable = true
        if scenario == "row-late-pan-transition" {
          touch.phase = .ended
          row.observer.touchesEnded([touch], with: event)
        }
        row.observer.reset()
        precondition(row.registeredTransitionCleanupSequence != nil, "Final cleanup must register a coordinator acquired after cancellation")
        row.click()
        precondition(row.props.pressCount == 0 && !target.selected)
      } else if scenario == "row-menu-cancellation" {
        touch.phase = .ended
        spin() // The phase changes, but no raw end/action is delivered.
        row.click()
        precondition(row.props.pressCount == 0 && !target.selected)
      } else if scenario == "row-superseded" {
        let next = RowHarness("second", delays: delays, interaction: interaction)
        let nextTouch = UITouch()
        next.receive(nextTouch)
        next.observer.touchesBegan([nextTouch], with: event)
        touch.phase = .ended
        row.observer.touchesEnded([touch], with: event)
        row.click()
        spin()
        precondition(row.props.pressCount == 0 && !target.selected, "Old fingers cannot reselect a superseded row")
        next.observer.invalidateTracking(reason: "test-finished")
      } else {
        if scenario == "row-long-hold" {
          touch.phase = .stationary
          spin(1.15)
          precondition(row.isTouchPrepared, "The real handler must not cancel a held candidate")
        }
        if scenario == "row-stale-reselect" { row.outside = true }
        touch.phase = .ended
        row.observer.touchesEnded([touch], with: event)
        if scenario == "row-detach-after-release" { row.observer.invalidateTracking(reason: "detached") }
        row.observer.reset()
        row.click()
        if scenario == "row-stale-reselect" {
          spin()
          precondition(row.props.pressCount == 0 && !target.selected)
        } else {
          precondition(row.props.pressCount == 1 && target.selected)
          // The owner completes while a touch-up select is still queued.
          interaction.clearNavigationTarget()
          target.deselect(animated: false)
          spin()
          precondition(!target.selected, "A queued select cannot resurrect a cleared owner")
        }
      }
      row.observer.invalidateTracking(reason: "test-finished")
    }

  default:
    preconditionFailure("Unknown scenario")
  }
  observer.invalidateTracking(reason: "test-finished")
  print("touch regression passed: " + scenario)
}

run(CommandLine.arguments[1])
`);
  execFileSync('swiftc', [swiftPath, '-o', executable], { stdio: 'pipe' });
});

after(() => { if (directory) rmSync(directory, { recursive: true, force: true }); });

for (const [scenario, description] of [
  ['long-hold', '持续按住超过原有 1 秒限制仍可在松手时正常结束'],
  ['delegate-only-reset', '只收到 shouldReceive 的候选在 reset 时清理'],
  ['missing-terminal', '实际触点结束但没有回调时清理，不合成点击'],
  ['missing-cancel', '实际触点取消但没有回调时清理'],
  ['delegate-only-terminal', '候选未收到 touchesBegan 也能按真实触点结束收尾'],
  ['cancelled', '取消和后续 reset 只清理一次'],
  ['detach-held', '解绑结束未松手的候选'],
  ['detach-released', '松手后的解绑和 reset 不取消等待中的 Button action'],
  ['view-disappeared', '观察宿主离开窗口时结束未完成候选'],
  ['overlapping-fingers', '多指交叠只取消一次，全部离开后恢复下一轮'],
  ['session-cancellation', '取消后不能被迟到 action 或旧 sequence 重新确认'],
  ['row-long-hold', '真实行处理器在两种触摸延迟下均允许长按松手点击'],
  ['row-menu-cancellation', '真实行处理器清理漏收结束的菜单候选并拒绝迟到点击'],
  ['row-stale-reselect', '移出取消后异步高亮任务不能重新选中'],
  ['row-superseded', '另一行接管后旧手指松开不重新选中旧行'],
  ['row-detach-after-release', '松手后解绑与 reset 保留真实 Button action 的确认资格'],
  ['row-late-pan-transition', '滚动取消后协调器较晚出现仍能注册最终清理'],
  ['row-late-cancel-transition', '触摸取消后的 reset 仍能补注册较晚出现的转场'],
]) {
  test(description, () => {
    assert.match(execFileSync(executable, [scenario], { encoding: 'utf8' }), /touch regression passed/);
  });
}

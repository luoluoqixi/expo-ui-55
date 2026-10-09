// 直接提取生产 Swift 回调，在隔离 harness 中验证选中集合和模式切换。
// 运行：node --test tests/native_list_selection.test.cjs（需要 macOS / Swift）
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { mkdtempSync, readFileSync, rmSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { test } = require('node:test');

const source = readFileSync(join(__dirname, '../ios/ListView.swift'), 'utf8');

function extractBlock(marker) {
  const start = source.indexOf(marker);
  assert.ok(start >= 0, `找不到 ${marker}`);
  const opening = source.indexOf('{', start);
  let depth = 1;
  let end = opening + 1;
  while (depth > 0 && end < source.length) {
    if (source[end] === '{') depth += 1;
    if (source[end] === '}') depth -= 1;
    end += 1;
  }
  assert.equal(depth, 0);
  return { declaration: source.slice(start, end), body: source.slice(opening + 1, end - 1) };
}

function callbackBody(marker, parameter) {
  const body = extractBlock(marker).body;
  const parameterPrefix = `${parameter} in`;
  assert.ok(body.trimStart().startsWith(parameterPrefix));
  return body.slice(body.indexOf(parameterPrefix) + parameterPrefix.length);
}

test('导航取消后单项 / 全选可用，模式切换按受控值清空或保留', () => {
  const directory = mkdtempSync(join(tmpdir(), 'expo-ui-selection-regression-'));
  try {
    const swiftPath = join(directory, 'main.swift');
    const executablePath = join(directory, 'regression');
    writeFileSync(swiftPath, `
import Foundation

// 不创建 UIKit cell；导航 session 和 selection 回调使用实际生产代码。
final class ListNavigationSelectionTarget {
  func matches(_ other: ListNavigationSelectionTarget?) -> Bool { self === other }
  func deselect(animated: Bool) {}
  func finishDeselectBackgroundAnimation() -> Int { 0 }
}

${extractBlock('private final class ListSelectionInteractionState').declaration}

private final class Harness {
  struct Props { var selection: [AnyHashable]? = [] }
  var props = Props()
  var selection = Set<AnyHashable>()
  var usesUIKitNavigationSelection = false
  let selectionInteraction = ListSelectionInteractionState()
  var events: [Set<AnyHashable>] = []

  static func getHashableSetFromEither(_ ids: [AnyHashable]?) -> Set<AnyHashable> {
    Set(ids ?? [])
  }

  func handleSelectionChange(selection: Set<AnyHashable>) {
    if Self.getHashableSetFromEither(props.selection) != selection {
      events.append(selection)
    }
  }

  func propsDidChange(_ newValue: [AnyHashable]?) {
    ${callbackBody('.onChange(of: props.selection)', 'newValue')}
  }

  func modeDidChange(_ usesUIKitSelection: Bool) {
    ${callbackBody('.onChange(of: usesUIKitNavigationSelection)', 'usesUIKitSelection')}
  }

  func selectionDidChange(_ newSelection: Set<AnyHashable>) {
    ${callbackBody('.onChange(of: selection)', 'newSelection')}
  }

  func select(_ ids: Set<AnyHashable>) {
    selection = ids
    // 模拟 onChange 修改 selection 时触发的下一轮回调。
    for _ in 0..<5 {
      let before = selection
      selectionDidChange(before)
      if before == selection {
        // 模拟调用方收到回调后更新受控值，再继续下一次用户选择。
        props.selection = Array(selection)
        return
      }
    }
    preconditionFailure("selection 回写未收敛")
  }

  func setMode(_ usesUIKitSelection: Bool) {
    usesUIKitNavigationSelection = usesUIKitSelection
    modeDidChange(usesUIKitSelection)
    selectionDidChange(selection)
  }
}

let all: Set<AnyHashable> = ["a", "b", "c"]
for cancelledID in all {
  let harness = Harness()
  let session = harness.selectionInteraction.begin(cancelledID)
  precondition(harness.selectionInteraction.shouldClearUnconfirmedSelection(cancelledID, session: session))
  precondition(!harness.selectionInteraction.confirm(cancelledID, session: session), "已取消的导航仍不得确认")
  harness.selectionInteraction.clearNavigationTarget()
  for _ in 0..<10 {
    harness.select(all)
    precondition(harness.selection == all, "全选不能排除旧导航 ID")
    precondition(harness.events.last == all, "回传全选必须包含全部 ID")
    harness.select([cancelledID])
    precondition(harness.events.last == [cancelledID], "旧导航 ID 也必须能手动选中")
    harness.select([])
    precondition(harness.events.last?.isEmpty == true, "取消全选必须回传空集合")
  }
}

private let harness = Harness()
for _ in 0..<10 {
  harness.props.selection = Array(all)
  harness.propsDidChange(harness.props.selection)
  precondition(harness.selection == all)
  harness.events = []
  harness.setMode(true)
  precondition(harness.selection.isEmpty, "退出编辑必须清空本地缓存")
  precondition(harness.events.isEmpty, "退出编辑不得向业务层回传旧选择")
  harness.props.selection = []
  harness.propsDidChange([])
  harness.setMode(false)
  precondition(harness.selection.isEmpty, "受控值保持为空时重新进入也不能恢复旧勾选")
  precondition(harness.events.isEmpty, "程序同步不应产生选择事件")
}

// 通用组件不强制清空业务选择：若调用方保留 ID，重新进入应按其受控值恢复。
harness.props.selection = Array(all)
harness.setMode(true)
harness.setMode(false)
precondition(harness.selection == all, "是否保留选择应由调用方决定")
print("selection regression passed")
`);
    execFileSync('swiftc', [swiftPath, '-o', executablePath], { stdio: 'pipe' });
    assert.match(execFileSync(executablePath, { encoding: 'utf8' }), /regression passed/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('保留单一 List 和 nil 导航 binding，不恢复结构性重建', () => {
  const block = extractBlock('private var selectionList: some View').declaration;
  assert.equal((block.match(/\bList\s*\(/g) ?? []).length, 1);
  assert.doesNotMatch(block, /\bif\b|\belse\b/);
  assert.match(block, /List\(selection: usesUIKitNavigationSelection \? nil : \$selection\)/);
  assert.doesNotMatch(source, /removingCancelledSelection/);
});

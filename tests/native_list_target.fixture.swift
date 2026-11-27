import UIKit

// PRODUCTION_TARGET

private final class RowHarness {
  private enum NavigationRowSelection {
    case table(UITableView, IndexPath)
    case collection(UICollectionView, IndexPath)
    case target(ListNavigationSelectionTarget)
  }
  // PRODUCTION_SELECT_ROW
  func restore(_ table: UITableView, at path: IndexPath) {
    selectNavigationRow(.table(table, path))
  }
  func restore(_ collection: UICollectionView, at path: IndexPath) {
    selectNavigationRow(.collection(collection, path))
  }
}

private final class Rows: NSObject, UICollectionViewDataSource, UITableViewDataSource {
  var sections = 2
  var count = 12
  func numberOfSections(in collectionView: UICollectionView) -> Int { sections }
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { count }
  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
  }
  func numberOfSections(in tableView: UITableView) -> Int { sections }
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { count }
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
  }
}

private let scenario = CommandLine.arguments[1]
private let rows = Rows()
private let source = UIView()
private let harness = RowHarness()
private let path = IndexPath(item: 1, section: scenario.hasSuffix("removed-section") ? 1 : 0)
private let frame = CGRect(x: 0, y: 0, width: 400, height: 800)

if scenario.contains("collection") {
  let collection = UICollectionView(frame: frame, collectionViewLayout: UICollectionViewFlowLayout())
  collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
  collection.dataSource = rows
  collection.reloadData()
  collection.layoutIfNeeded()
  let target = ListNavigationSelectionTarget(collectionView: collection, indexPath: path, sourceView: source)
  target.select(highlighted: true)
  precondition(collection.indexPathsForSelectedItems?.contains(path) == true)
  target.deselect(animated: false)
  // 模拟返回时 SwiftUI 已经重建 / 清空原列表的数据源。
  if scenario.hasSuffix("removed-section") { rows.sections = 1 }
  if scenario.hasSuffix("removed-item") { rows.count = 1 }
  collection.reloadData()
  collection.layoutIfNeeded()
  if scenario.hasPrefix("target-") {
    target.restoreSelection()
  } else {
    harness.restore(collection, at: path)
  }
  if scenario.hasSuffix("valid") {
    precondition(collection.indexPathsForSelectedItems == [path], "有效的行仍应恢复选中")
    precondition(collection.cellForItem(at: path)?.isHighlighted != true)
  } else {
    precondition(collection.indexPathsForSelectedItems?.isEmpty != false, "失效路径不能进入 UIKit 的选中集合")
    target.deselect(animated: true)
    // 原列表恢复后，同一个 target 仍可使用，不能永久取消其导航 session。
    rows.sections = 2
    rows.count = 12
    collection.reloadData()
    collection.layoutIfNeeded()
    target.restoreSelection()
    precondition(collection.indexPathsForSelectedItems == [path])
  }
} else {
  let table = UITableView(frame: frame)
  table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
  table.dataSource = rows
  table.reloadData()
  table.layoutIfNeeded()
  let target = ListNavigationSelectionTarget(tableView: table, indexPath: path, sourceView: source)
  target.select(highlighted: true)
  precondition(table.indexPathForSelectedRow == path)
  target.deselect(animated: false)
  if scenario.hasSuffix("removed-section") { rows.sections = 1 }
  if scenario.hasSuffix("removed-row") { rows.count = 1 }
  table.reloadData()
  table.layoutIfNeeded()
  if scenario.hasPrefix("target-") {
    target.restoreSelection()
  } else {
    harness.restore(table, at: path)
  }
  if scenario.hasSuffix("valid") {
    precondition(table.indexPathForSelectedRow == path, "有效的行仍应恢复选中")
    precondition(table.cellForRow(at: path)?.isHighlighted != true)
  } else {
    precondition(table.indexPathForSelectedRow == nil, "失效路径不能进入 UIKit 的选中集合")
    target.deselect(animated: true)
    rows.sections = 2
    rows.count = 12
    table.reloadData()
    table.layoutIfNeeded()
    target.restoreSelection()
    precondition(table.indexPathForSelectedRow == path)
  }
}
print("selection target regression passed: \(scenario)")

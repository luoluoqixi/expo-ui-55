// 使用真实 UIKit 验证列表重建后的选中恢复；需要已启动的 iOS Simulator。
// EXPO_UI_TEST_SIMULATOR_UDID 可指定设备，否则使用当前已启动的设备。
const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const { mkdtempSync, readFileSync, rmSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { after, before, test } = require('node:test');

const source = readFileSync(join(__dirname, '../ios/ListView.swift'), 'utf8');
function extractBlock(marker) {
  const start = source.indexOf(marker);
  assert.ok(start >= 0, `找不到 ${marker}`);
  let end = source.indexOf('{', start) + 1;
  let depth = 1;
  while (depth > 0 && end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
    end++;
  }
  assert.equal(depth, 0);
  return source.slice(start, end);
}

let device;
if (process.platform === 'darwin') {
  const devices = JSON.parse(execFileSync('xcrun', ['simctl', 'list', 'devices', 'booted', '-j']));
  const booted = Object.values(devices.devices).flat();
  device = booted.find(({ udid }) => udid === process.env.EXPO_UI_TEST_SIMULATOR_UDID)
    ?? (process.env.EXPO_UI_TEST_SIMULATOR_UDID ? undefined : booted[0]);
}
let directory;
let executable;
before(() => {
  if (!device) return;
  directory = mkdtempSync(join(tmpdir(), 'expo-ui-target-regression-'));
  executable = join(directory, 'regression');
  const swiftPath = join(directory, 'main.swift');
  const swift = readFileSync(join(__dirname, 'native_list_target.fixture.swift'), 'utf8')
    .replace('// PRODUCTION_TARGET', extractBlock('final class ListNavigationSelectionTarget'))
    .replace('// PRODUCTION_SELECT_ROW', extractBlock('  private func selectNavigationRow('));
  writeFileSync(swiftPath, swift);
  execFileSync('xcrun', [
    '--sdk', 'iphonesimulator', 'swiftc', swiftPath,
    '-target', `${process.arch === 'arm64' ? 'arm64' : 'x86_64'}-apple-ios16.0-simulator`,
    '-o', executable,
  ], { stdio: 'pipe' });
});
after(() => { if (directory) rmSync(directory, { recursive: true, force: true }); });

for (const scenario of [
  'target-collection-removed-item', 'target-collection-removed-section',
  'target-table-removed-row', 'target-table-removed-section',
  'row-collection-removed-item', 'row-collection-removed-section',
  'row-table-removed-row', 'row-table-removed-section',
  'target-collection-valid', 'target-table-valid',
  'row-collection-valid', 'row-table-valid',
]) {
  test(`原生导航选中恢复：${scenario}`, { skip: device ? false : '需要已启动的 iOS Simulator' }, () => {
    const result = spawnSync('xcrun', ['simctl', 'spawn', device.udid, executable, scenario], { encoding: 'utf8' });
    assert.equal(result.status, 0, (result.stdout + result.stderr).slice(-3000));
    assert.match(result.stdout, /selection target regression passed/);
  });
}

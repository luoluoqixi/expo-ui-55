// Exercise production Swift transition capture/qualification without UIKit.
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { mkdtempSync, readFileSync, rmSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { test } = require('node:test');

const source = readFileSync(join(__dirname, '../ios/ListView.swift'), 'utf8');
function extractBlock(marker) {
  const start = source.indexOf(marker);
  assert.ok(start >= 0, 'Missing ' + marker);
  const opening = source.indexOf('{', start);
  let depth = 1;
  let end = opening + 1;
  while (depth > 0 && end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
    end++;
  }
  assert.equal(depth, 0);
  return { declaration: source.slice(start, end), body: source.slice(opening + 1, end - 1) };
}
// macOS treats iOS availability as satisfied; exercise both branches explicitly.
const legacyAvailability = (s) => s.replaceAll('#unavailable(iOS 19.0)', 'isLegacyIOS');

test('cancelled pop cannot lend its session or finalization skip to another transition', () => {
  const directory = mkdtempSync(join(tmpdir(), 'expo-ui-transition-regression-'));
  try {
    const capture = legacyAvailability(extractBlock('private func navigationSelectionSession(').declaration);
    const appearance = extractBlock('  func deselectNavigationRowAlongsideTransition(').body;
    const qualification = legacyAvailability(appearance.slice(0, appearance.indexOf('    let session =')))
      .replace(/\breturn\b/g, 'return false');
    const swift = readFileSync(join(__dirname, 'native_list_transition.fixture.swift'), 'utf8')
      .replace('// PRODUCTION_CAPTURE', capture)
      .replace('// PRODUCTION_QUALIFICATION', qualification);
    const swiftPath = join(directory, 'main.swift');
    const executablePath = join(directory, 'regression');
    writeFileSync(swiftPath, swift);
    execFileSync('swiftc', [swiftPath, '-o', executablePath], { stdio: 'pipe' });
    assert.match(execFileSync(executablePath, { encoding: 'utf8' }), /transition regression passed/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

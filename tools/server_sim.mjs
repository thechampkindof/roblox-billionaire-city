#!/usr/bin/env node
// Headless server simulation: boots the real server code against a Roblox shim and plays
// the Phase 1 loop through the same intents a client sends.
//
// Usage: node tools/server_sim.mjs

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRuntime } from './luau_runtime.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const runtime = await createRuntime(repoRoot, ['src', 'tools']);

console.log('Billionaire City Tycoon — headless server simulation\n');

let summary;
try {
  const sim = runtime.runModule('tools/harness/ServerSim');
  // The simulation prints each check as it runs; JS only reports the totals.
  sim.rawGet('run').call();
  summary = sim.rawGet('summary').call()[0];
} catch (error) {
  console.error(`\nSimulation crashed:\n${error?.stack ?? error}`);
  process.exit(1);
}

const passed = Number(summary.rawGet('passed'));
const failed = Number(summary.rawGet('failed'));
console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) {
  process.exit(1);
}
console.log('RESULT: the server loop runs end to end');

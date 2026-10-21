#!/usr/bin/env node
// Headless client boot + interaction test: installs a fake LocalPlayer, runs the real
// client bundle, pushes a real snapshot and simulates taps on the world and in the UI.
//
// Usage: node tools/client_sim.mjs

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRuntime } from './luau_runtime.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const runtime = await createRuntime(repoRoot, ['src', 'tools']);

console.log('Billionaire City Tycoon — headless client simulation\n');

let summary;
try {
  const sim = runtime.runModule('tools/harness/ClientSim');
  sim.rawGet('run').call();
  summary = sim.rawGet('summary').call()[0];
} catch (error) {
  console.error(`\nSimulation crashed:\n${error?.stack ?? error}`);
  process.exit(1);
}

const passed = Number(summary.rawGet('passed'));
const failed = Number(summary.rawGet('failed'));
console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
console.log('RESULT: the client boots, renders and routes input');

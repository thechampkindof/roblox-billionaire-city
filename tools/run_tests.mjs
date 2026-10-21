#!/usr/bin/env node
// Headless test runner for the pure-Luau core and content suites.
//
// Usage: node tools/run_tests.mjs [pathFilter]
//
// This is the sandbox-friendly runner. CI uses `lune run tests/AllTests.luau`
// (official Luau runtime) — both load the same spec modules through the same
// `require(script.Parent...)` semantics.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRuntime } from './luau_runtime.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const filter = process.argv[2] || '';

function specFiles() {
	const files = [];
	for (const folder of ['Core', 'Config', 'Net', 'Util']) {
		const dir = path.join(repoRoot, 'tests', folder);
		if (!fs.existsSync(dir)) continue;
		for (const entry of fs.readdirSync(dir).sort()) {
			if (entry.endsWith('.spec.luau')) {
				files.push({ group: folder, name: entry.slice(0, -'.spec.luau'.length) });
			}
		}
	}
	return files;
}

const runtime = await createRuntime(repoRoot);
const framework = runtime.runModule('tests/Framework');

const specs = specFiles().filter((spec) => !filter || `${spec.group}/${spec.name}`.includes(filter));
if (specs.length === 0) {
	console.error(`No specs matched "${filter}"`);
	process.exit(1);
}

console.log(`Running ${specs.length} spec files with Luau (WASM)\n`);

let loadFailures = 0;
for (const spec of specs) {
	try {
		runtime.runModule(`tests/${spec.group}/${spec.name}.spec`);
	} catch (error) {
		loadFailures += 1;
		console.error(`  FAIL loading ${spec.group}/${spec.name}: ${error?.message ?? error}`);
	}
}

const runFunction = framework.rawGet('run');
const results = runFunction.call(true);
const summary = results[0].toObject();
const failed = Number(summary.failed);
const passed = Number(summary.passed);

console.log(`\n${passed} passed, ${failed} failed${loadFailures ? `, ${loadFailures} spec file(s) failed to load` : ''}`);
if (failed > 0 || loadFailures > 0) {
	process.exit(1);
}

#!/usr/bin/env node
// Runs a Luau tool from `tools/` with a minimal host: `print`, `warn`, `os`, `require`
// and the `ARGS` global (so tools can read flags such as `--smoke`). A tool signals
// failure by setting `EXIT_CODE` to a non-zero number.
//
// Usage: node tools/run_luau.mjs tools/economy_sim.luau --smoke

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRuntime } from './luau_runtime.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const [scriptPath, ...args] = process.argv.slice(2);

if (!scriptPath) {
	console.error('usage: node tools/run_luau.mjs <script.luau> [args...]');
	process.exit(2);
}

const runtime = await createRuntime(repoRoot);
const elements = args.map((value) => JSON.stringify(value)).join(', ');
runtime.lua.globals.set('ARGS', runtime.lua.execute(`return { ${elements} }`)[0]);
runtime.lua.globals.set('EXIT_CODE', 0);

let failed = false;
try {
	const instancePath = scriptPath.replace(/^\.?\//, '').replace(/\.luau$/, '');
	runtime.runModule(instancePath);
} catch (error) {
	failed = true;
	console.error(`\n${error?.message ?? error}`);
}

const exitCode = Number(runtime.lua.globals.rawGet('EXIT_CODE'));
if (failed || (Number.isFinite(exitCode) && exitCode !== 0)) {
	process.exit(1);
}

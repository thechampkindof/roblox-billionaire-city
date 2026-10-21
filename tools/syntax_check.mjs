#!/usr/bin/env node
// Compiles every Luau file in the repo with the Luau compiler (no execution).
//
// This is the fastest honest syntax/parse gate we can run outside Roblox: it catches
// typos, bad `--!strict` annotations and broken requires-of-syntax long before Studio.
// Type checking is NOT performed here (Luau's type checker needs the analyzer pass);
// that is why CI still runs tooling that ships with Studio-compatible docs.
//
// Usage: node tools/syntax_check.mjs [roots...]

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Lua } from '@luau-rs/luau';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DEFAULT_ROOTS = ['src', 'tests', 'tools'];
const roots = process.argv.slice(2).length > 0 ? process.argv.slice(2) : DEFAULT_ROOTS;
const SKIP_DIRS = new Set(['node_modules', 'build', '.git']);

function walk(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, files);
    else if (/\.(luau|lua)$/.test(entry.name)) files.push(full);
  }
  return files;
}

const lua = await Lua.create({ sandbox: true });

let checked = 0;
const failures = [];

for (const root of roots) {
  const base = path.resolve(repoRoot, root);
  if (!fs.existsSync(base)) continue;
  for (const file of walk(base)) {
    const source = fs.readFileSync(file, 'utf8');
    checked += 1;
    try {
      lua.compile(source);
    } catch (error) {
      failures.push({ file: path.relative(repoRoot, file), message: String(error?.message ?? error) });
    }
  }
}

if (failures.length > 0) {
  for (const failure of failures) {
    const line = /\[(\d+)\]|\b(\d+):(\d+)\b/.exec(failure.message);
    const where = line ? ` (line ${line[1] ?? line[2]})` : '';
    console.error(`FAIL ${failure.file}${where}\n     ${failure.message.split('\n')[0]}`);
  }
  console.error(`\n${failures.length} of ${checked} files failed to compile`);
  process.exit(1);
}

console.log(`OK ${checked} Luau files compile`);

#!/usr/bin/env node
// Static wiring check — the things that break a Rojo project at runtime, caught without
// Studio:
//
//   1. every `require(script.Parent...)` points at a real module,
//   2. every `Content.x.y` / `Balance.x.y` path actually exists on the data tables,
//   3. every `Foo.Bar(` call resolves to a `function Foo.Bar` / `Foo.Bar =` in the module
//      that exports `Foo`,
//   4. every intent registered by a service has a schema, and every schema is handled,
//   5. every `Flags.get("...")` names a declared flag.
//
// Nothing here executes Roblox APIs; the pure config modules are loaded through the same
// headless runtime the test suite uses.
//
// Usage: node tools/wiring_check.mjs

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRuntime } from './luau_runtime.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SKIP_DIRS = new Set(['node_modules', 'build', '.git']);
const ROOTS = ['src', 'tests', 'tools'];

const problems = [];
const note = (file, message) => problems.push(`${path.relative(repoRoot, file)}: ${message}`);

function walk(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, files);
    else if (/\.luau$/.test(entry.name)) files.push(full);
  }
  return files;
}

const files = ROOTS.flatMap((root) => {
  const dir = path.join(repoRoot, root);
  return fs.existsSync(dir) ? walk(dir) : [];
});

const rawSources = new Map(files.map((file) => [file, fs.readFileSync(file, 'utf8')]));

// Strip comments so examples inside doc blocks never look like real code.
function stripComments(source) {
  return source.replace(/--\[\[.*?\]\]/gs, '').replace(/--[^\n]*/g, '');
}

// Code used for `require`/call scanning; `rawSources` keeps comments for the docs check.
const sources = new Map([...rawSources].map(([file, source]) => [file, stripComments(source)]));

// --- 1. requires ---------------------------------------------------------------

function resolveRequire(fromFile, chain) {
  const segments = chain.split('.');
  let dir = path.dirname(fromFile);
  let index = 0;
  // `script.Parent` is the folder that contains the file, so only the *second* and
  // later `.Parent` segments walk upwards.
  while (segments[index] === 'Parent') {
    if (index > 0) dir = path.dirname(dir);
    index += 1;
  }
  const rest = segments.slice(index);
  if (rest.length === 0) return null;
  const candidate = path.join(dir, ...rest);
  for (const suffix of ['.luau', '/init.luau', '/init.client.luau', '/init.server.luau']) {
    const full = candidate + suffix;
    if (fs.existsSync(full)) return full;
  }
  return null;
}

const requirePattern = /require\(script((?:\.Parent)*)\.([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*)\)/g;
for (const [file, source] of sources) {
  for (const match of source.matchAll(requirePattern)) {
    const chain = [...match[1].split('.').filter(Boolean), ...match[2].split('.')].join('.');
    if (resolveRequire(file, chain) === null) {
      note(file, `require(script.${chain}) does not resolve to a file`);
    }
  }
}

// --- 2. Content / Balance paths -------------------------------------------------

const runtime = await createRuntime(repoRoot);

function luaField(handle, key) {
  if (!handle || typeof handle.rawGet !== 'function') return undefined;
  try {
    return handle.rawGet(key);
  } catch {
    return undefined;
  }
}

const content = runtime.runModule('src/shared/Config/Init');
const balance = luaField(content, 'Balance');
const flags = luaField(content, 'Flags');

const chains = new Map(); // root -> Set(path)
function collectChains(source, rootName, target) {
  const pattern = new RegExp(`(?<![\\w.])${rootName}\\.([A-Za-z_]\\w*(?:\\.[A-Za-z_]\\w*)*)`, 'g');
  for (const match of source.matchAll(pattern)) {
    const chain = match[1];
    if (!target.has(chain)) target.set(chain, true);
  }
}

const contentChains = new Map();
const balanceChains = new Map();
for (const [file, source] of sources) {
  collectChains(source, 'Content', contentChains);
  collectChains(source, 'Balance', balanceChains);
}

function missingContentPath(chain) {
  let node = content;
  for (const part of chain.split('.')) {
    const next = luaField(node, part);
    if (next === undefined || next === null) return part;
    node = next;
  }
  return null;
}

// Table handles report `null` for missing keys and `undefined` when there is no handle.
for (const chain of contentChains.keys()) {
  if (chain.startsWith('buildingById') || chain.startsWith('upgradeById') || chain.startsWith('parcelById')) {
    // Indexed lookups: only the table itself must exist.
    const first = chain.split('.')[0];
    if (luaField(content, first) == null) note('(multiple)', `Content.${first} missing`);
    continue;
  }
  const missing = missingContentPath(chain);
  if (missing) note('(multiple)', `Content.${chain} is missing "${missing}"`);
}

function missingBalancePath(chain) {
  let node = balance;
  for (const part of chain.split('.')) {
    const next = luaField(node, part);
    if (next === undefined || next === null) return part;
    node = next;
  }
  return null;
}
for (const chain of balanceChains.keys()) {
  const missing = missingBalancePath(chain);
  if (missing) note('(multiple)', `Balance.${chain} is missing "${missing}"`);
}

// --- 3. service methods ---------------------------------------------------------

// Module name -> exported member names, scanned from source.
const exportsByModule = new Map();
const moduleNamePattern = /function\s+([A-Za-z_]\w*)[.:]([A-Za-z_]\w*)/g;
const fieldPattern = /^\s*([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*(?==)/gm;
const typePattern = /export\s+type\s+([A-Za-z_]\w*)/g;
const definitionPattern = /function\s+([A-Za-z_]\w*)[.:]([A-Za-z_]\w*)/g;
for (const [file, source] of sources) {
  // Two functions with the same exported name silently shadow each other (a service's
  // lifecycle `Start()` versus a gameplay `Start(player, ...)` is the classic case).
  const defined = new Map();
  for (const match of source.matchAll(definitionPattern)) {
    const key = `${match[1]}.${match[2]}`;
    defined.set(key, (defined.get(key) ?? 0) + 1);
  }
  for (const [key, times] of defined) {
    if (times > 1) note(file, `${key} is defined ${times} times (later definition wins)`);
  }
}

for (const [file, source] of sources) {
  const name = path.basename(file).replace(/(?:\.[a-z]+)?\.luau$/, '');
  const members = new Set();
  for (const match of source.matchAll(moduleNamePattern)) members.add(match[2]);
  for (const match of source.matchAll(fieldPattern)) members.add(match[2]);
  for (const match of source.matchAll(typePattern)) members.add(match[1]);
  if (members.size === 0) continue;
  // Two modules can share a basename (`Config/Objectives`, `Core/Objectives`); keep both.
  const existing = exportsByModule.get(name);
  if (existing) existing.push({ file, members });
  else exportsByModule.set(name, [{ file, members }]);
}

// Local aliases: `local FooService = require(script.Parent.X)` -> `X`.
const aliasPattern = /local\s+([A-Za-z_]\w*)\s*=\s*require\(script((?:\.Parent)*)\.([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*)\)\s*(?==|$)/gm;
for (const [file, source] of sources) {
  const aliases = new Map();
  for (const match of source.matchAll(aliasPattern)) {
    const modules = match[3].split('.');
    aliases.set(match[1], modules[modules.length - 1]);
  }
  for (const [alias, moduleName] of aliases) {
    const exported = exportsByModule.get(moduleName);
    if (!exported) continue;
    const callPattern = new RegExp(`(?<![\\w.])${alias}\\.([A-Za-z_]\\w*)`, 'g');
    for (const match of source.matchAll(callPattern)) {
      const member = match[1];
      if (/^(Name|Dependencies)$/.test(member)) continue;
      if (!exported.some((entry) => entry.members.has(member))) {
        note(file, `${alias}.${member} is not exported by any ${moduleName}.luau`);
      }
    }
  }
}

// --- 4. intents -----------------------------------------------------------------

const remotesSource = sources.get(path.join(repoRoot, 'src/shared/Net/Remotes.luau')) ?? '';
const schemas = new Set(
  [...remotesSource.matchAll(/^\t([A-Za-z]\w*)\s*=\s*\{\s*fields\s*=/gm)].map((m) => m[1]),
);
const registered = new Set();
const netServiceFile = path.join(repoRoot, 'src/server/Services/NetService.luau');
const netSource = sources.get(netServiceFile) ?? '';
for (const match of netSource.matchAll(/NetService\.Register\("([A-Za-z]+)"/g)) {
  registered.add(match[1]);
  if (!schemas.has(match[1])) note(netServiceFile, `intent "${match[1]}" is registered but has no schema`);
}
for (const schema of schemas) {
  if (!registered.has(schema)) note(netServiceFile, `schema "${schema}" has no handler`);
}

// Client intents must all be real.
for (const [file, source] of sources) {
  if (!file.includes(`${path.sep}client${path.sep}`)) continue;
  for (const match of source.matchAll(/StateController\.Send\("([A-Za-z]+)"/g)) {
    if (!schemas.has(match[1])) note(file, `client sends unknown intent "${match[1]}"`);
  }
}

// --- 5. flags -------------------------------------------------------------------

const declaredFlags = flags && typeof flags === 'object' ? flags : null;
for (const [file, source] of sources) {
  for (const match of source.matchAll(/Flags\.get\("([A-Za-z0-9_]+)"\)/g)) {
    const name = match[1];
    if (declaredFlags && luaField(declaredFlags, name) === undefined) {
      note(file, `flag "${name}" is not declared in Config/Flags.luau`);
    }
  }
}

// --- report ---------------------------------------------------------------------

const unique = [...new Set(problems)];
if (unique.length > 0) {
  for (const problem of unique) console.error(`FAIL ${problem}`);
  console.error(`\n${unique.length} wiring problem(s)`);
  process.exit(1);
}
console.log(`OK ${files.length} files, ${contentChains.size} Content paths, ${balanceChains.size} Balance paths, ${schemas.size} intents, ${exportsByModule.size} modules`);

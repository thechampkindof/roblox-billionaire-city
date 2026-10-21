// Headless Luau runtime + Roblox-style module loader for the repo's pure-Luau code.
//
// Why this exists: the CI toolchain (Rokit + Lune + Rojo) cannot run inside every
// sandbox, so the same test suites are runnable through the Luau WASM runtime that
// ships with @luau-rs/luau. It implements the exact `require(script.Parent...)`
// semantics the game code uses in Roblox: modules are instances in a tree, `script`
// points at the module being executed, and requires are cached.

import fs from 'node:fs';
import path from 'node:path';
import { Lua } from '@luau-rs/luau';

const MODULE_EXTENSIONS = new Set(['.luau', '.lua']);

function listFiles(root, relative = '') {
	const dir = path.join(root, relative);
	const entries = fs.readdirSync(dir, { withFileTypes: true });
	const files = [];
	for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
		const rel = relative ? path.join(relative, entry.name) : entry.name;
		if (entry.isDirectory()) {
			files.push(...listFiles(root, rel));
		} else if (MODULE_EXTENSIONS.has(path.extname(entry.name))) {
			files.push(rel);
		}
	}
	return files;
}

/** Builds a virtual Roblox-like instance tree from `roots` (e.g. ['src', 'tests', 'tools']). */
export function buildTree(repoRoot, roots) {
	const nodes = new Map();
	const rootNode = {
		path: '',
		name: 'Root',
		kind: 'folder',
		parentPath: null,
		children: [],
		source: null,
	};
	nodes.set('', rootNode);

	const ensureFolder = (segments) => {
		if (segments.length === 0) return rootNode;
		const key = segments.join('/');
		let node = nodes.get(key);
		if (!node) {
			const parent = ensureFolder(segments.slice(0, -1));
			node = {
				path: key,
				name: segments[segments.length - 1],
				kind: 'folder',
				parentPath: parent.path,
				children: [],
				source: null,
			};
			nodes.set(key, node);
			parent.children.push(node);
		}
		return node;
	};

	for (const root of roots) {
		ensureFolder([root]);
		for (const file of listFiles(path.join(repoRoot, root))) {
			const segments = file.split(path.sep);
			const base = segments.pop();
			const parent = ensureFolder([root, ...segments]);
			const ext = path.extname(base);
			const name = base.slice(0, base.length - ext.length);
			// Rojo: `init*.luau` turns the folder itself into a script.
			if (name.startsWith('init')) {
				parent.source = fs.readFileSync(path.join(repoRoot, root, file), 'utf8');
				parent.kind = name.includes('.server') || name.includes('.client') ? 'script' : 'module';
				continue;
			}
			const node = {
				path: [root, ...segments, name].join('/'),
				name,
				kind: 'module',
				parentPath: parent.path,
				children: [],
				source: fs.readFileSync(path.join(repoRoot, root, file), 'utf8'),
			};
			nodes.set(node.path, node);
			parent.children.push(node);
		}
	}

	return { nodes, root: rootNode };
}

/** Creates a Luau state with `require`, `script` and the instance tree wired up. */
export async function createRuntime(repoRoot, roots = ['src', 'tests', 'tools']) {
	const lua = await Lua.create({ sandbox: true });
	const { nodes, root } = buildTree(repoRoot, roots);

	const nodeHandles = new Map();
	const buildLuaNode = (node) => {
		if (nodeHandles.has(node.path)) return nodeHandles.get(node.path);
		const table = lua.execute('return {}')[0];
		nodeHandles.set(node.path, table);
		table.rawSet('Name', node.name);
		table.rawSet('__path', node.path);
		for (const child of node.children) {
			table.rawSet(child.name, buildLuaNode(child));
		}
		return table;
	};
	buildLuaNode(root);
	for (const node of nodes.values()) {
		if (node.parentPath === null) continue;
		nodeHandles.get(node.path).rawSet('Parent', nodeHandles.get(node.parentPath));
	}
	lua.globals.set('__ROOT', nodeHandles.get(''));

	const cache = new Map();
	const loading = new Set();

	const requireNode = lua.createFunction((handle) => {
		const nodePath = handle.rawGet('__path');
		const node = nodes.get(nodePath);
		if (!node) throw new Error(`require: unknown instance "${nodePath}"`);
		if (node.kind === 'folder') throw new Error(`require: "${nodePath}" is a folder, not a ModuleScript`);
		if (cache.has(nodePath)) return cache.get(nodePath);
		if (loading.has(nodePath)) throw new Error(`require: circular dependency at "${nodePath}"`);
		if (!node.source) throw new Error(`require: "${nodePath}" has no source`);
		loading.add(nodePath);
		const previousScript = lua.globals.rawGet('script');
		try {
			lua.globals.set('script', nodeHandles.get(nodePath));
			const result = lua.execute(node.source);
			const value = result.length > 0 && result[0] !== undefined ? result[0] : null;
			cache.set(nodePath, value);
			return value;
		} finally {
			loading.delete(nodePath);
			// Nested requires change `script`; restore the caller's instance.
			if (previousScript !== undefined) lua.globals.set('script', previousScript);
		}
	});
	lua.globals.set('require', requireNode);

	lua.globals.set(
		'print',
		lua.createFunction(...variadicLog(console.log)),
	);
	lua.globals.set(
		'warn',
		lua.createFunction(...variadicLog(console.error)),
	);
	lua.globals.set(
		'os',
		lua.execute('return { time = function() return 0 end, clock = function() return 0 end }')[0],
	);

	const callRequire = (handle) => {
		const values = requireNode.call(handle);
		return values.length > 0 ? values[0] : null;
	};

	const runModule = (instancePath) => {
		const handle = nodeHandles.get(instancePath);
		if (!handle) throw new Error(`runModule: no instance "${instancePath}"`);
		return callRequire(handle);
	};

	const runSource = (source, chunkName = 'chunk') => lua.execute(source, { chunkName });

	return { lua, runModule, runSource, nodes, root, nodeHandles };
}

function variadicLog(writer) {
	const callback = (...args) => writer(...args.map(formatValue));
	// `createFunction` takes (callback, options); a variadic signature is requested
	// by passing no argument decoder array, which the runtime treats as "any".
	return [callback];
}

export function formatValue(value) {
	if (value === null || value === undefined) return 'nil';
	if (typeof value === 'object' && typeof value.toObject === 'function') {
		try {
			return JSON.stringify(value.toObject());
		} catch {
			return '[table]';
		}
	}
	return String(value);
}

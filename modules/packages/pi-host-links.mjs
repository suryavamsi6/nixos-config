#!/usr/bin/env node
// pi-host-links — keep pi extension packages able to resolve host-provided modules.
//
// Why this exists
// ---------------
// pi hands extension packages a set of modules it already has loaded
// (@earendil-works/pi-ai, pi-agent-core, pi-coding-agent, pi-tui). That mapping is
// applied to imports it can see statically. An extension that loads one of those
// packages dynamically — pi-agent-browser-native's lib/tool-surface.js does
// `await import("@earendil-works/pi-ai")` — falls through to Node's ordinary
// filesystem resolution, which walks up from the extension file to
//
//   ~/.pi/agent/npm/node_modules/@earendil-works/pi-ai
//
// That directory is reified by npm from the registry, and nothing there declares
// these packages as dependencies (the extension manifests list them as
// peerDependencies precisely so pi provides them), so every npm install,
// uninstall, update, dedupe, ci or prune deletes them as extraneous. The next pi
// start then fails with:
//
//   Cannot find package '@earendil-works/pi-ai' imported from
//   .../pi-agent-browser-native/dist/extensions/agent-browser/lib/tool-surface.js
//
// What it does
// ------------
// Re-creates those symlinks, always pointing at the copy belonging to the *running*
// pi installation (the npx cache directory that owns node_modules/.bin/pi). A
// second downloaded copy would not share host state — e.g. getCurrentSystemMessage()
// reads state set by the host's own instance — so the link target is the host's
// real directory, which Node canonicalises to the same module instance.
//
// It is idempotent and cheap: it exits after a few lstat calls when every link it
// recorded in .pi-host-links.json is still intact, and only re-scans the installed
// extension packages (to rediscover which host packages they import) when npm has
// removed something, --full is passed, or no state has been recorded yet.
//
// Invoked from two places, both of which repair before the broken state is used:
//   * the Nix `pi` wrapper (modules/packages/dev.nix) — before pi starts
//   * ~/.pi/agent/bin/pi-npm — after every npm invocation pi performs
//
// Usage: pi-host-links [--check] [--full] [--verbose]

import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  rmSync,
  statSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join } from "node:path";
import { homedir } from "node:os";

const SPECS = [
  "@earendil-works/pi-ai",
  "@earendil-works/pi-agent-core",
  "@earendil-works/pi-coding-agent",
  "@earendil-works/pi-tui",
];

const SCAN_EXTENSIONS = new Set([".js", ".mjs", ".cjs", ".jsx", ".ts", ".mts", ".cts", ".tsx"]);
const SCAN_MAX_FILE_BYTES = 2_000_000;
const SCAN_MAX_FILES = 8000;
const SCAN_MAX_TOTAL_BYTES = 80_000_000;

const argv = new Set(process.argv.slice(2));
const VERBOSE = argv.has("--verbose") || process.env.PI_HOST_LINKS_VERBOSE === "1";
const CHECK = argv.has("--check");
const FULL = argv.has("--full");

const agentDir = process.env.PI_AGENT_DIR || join(homedir(), ".pi", "agent");
const projectDir = join(agentDir, "npm");
const modulesDir = join(projectDir, "node_modules");
const statePath = join(projectDir, ".pi-host-links.json");

const log = (message) => {
  if (VERBOSE) process.stderr.write(`pi-host-links: ${message}\n`);
};

function isDirectory(path) {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function mtimeMs(path) {
  try {
    return statSync(path).mtimeMs;
  } catch {
    return -1;
  }
}

function realOrNull(path) {
  try {
    return realpathSync(path);
  } catch {
    return null;
  }
}

function lstatOrNull(path) {
  try {
    return lstatSync(path);
  } catch {
    return null;
  }
}

/** A link counts as healthy only when it resolves to the intended host copy. */
function isValidLink(linkPath, target) {
  if (!target) return false;
  const stats = lstatOrNull(linkPath);
  if (!stats || !stats.isSymbolicLink()) return false;
  const resolved = realOrNull(linkPath);
  const wanted = realOrNull(target);
  if (!resolved || !wanted || resolved !== wanted) return false;
  return existsSync(join(linkPath, "package.json"));
}

/** Ordered list of places a host-provided package may legitimately live. */
function hostSourceCandidates(spec) {
  const candidates = [];
  const push = (path) => {
    if (path.startsWith(`${modulesDir}/`)) return;
    candidates.push(path);
  };

  const npxRoot = join(homedir(), ".npm", "_npx");
  const runners = [];
  const rest = [];
  let npxDirs = [];
  try {
    npxDirs = readdirSync(npxRoot).map((entry) => join(npxRoot, entry));
  } catch {
    npxDirs = [];
  }
  for (const dir of npxDirs) {
    // The npx directory that provides `pi` on PATH is the installation pi runs from.
    if (existsSync(join(dir, "node_modules", ".bin", "pi"))) runners.push(dir);
    else rest.push(dir);
  }
  const byNewest = (a, b) => mtimeMs(b) - mtimeMs(a);
  runners.sort(byNewest);
  rest.sort(byNewest);

  for (const dir of [...runners, ...rest]) {
    push(join(dir, "node_modules", "@earendil-works", "pi-coding-agent", "node_modules", spec));
    push(join(dir, "node_modules", spec));
  }

  const globalRoots = [
    join(homedir(), ".npm-global", "lib", "node_modules"),
    `/etc/profiles/per-user/${process.env.USER ?? ""}/lib/node_modules`,
    "/usr/local/lib/node_modules",
    "/usr/lib/node_modules",
  ];
  for (const root of globalRoots) {
    push(join(root, "@earendil-works", "pi-coding-agent", "node_modules", spec));
    push(join(root, spec));
  }

  return candidates;
}

function findHostSource(spec) {
  for (const candidate of hostSourceCandidates(spec)) {
    if (existsSync(join(candidate, "package.json"))) return candidate;
  }
  return null;
}

/** Point `linkPath` at the host copy, replacing anything npm left behind. */
function ensureLink(linkPath, target) {
  const wanted = realOrNull(target);
  if (!wanted) return "skipped";
  if (isValidLink(linkPath, wanted)) return "intact";

  const existing = lstatOrNull(linkPath);
  if (existing) {
    if (existing.isDirectory() && !existing.isSymbolicLink()) {
      rmSync(linkPath, { recursive: true, force: true });
    } else {
      unlinkSync(linkPath);
    }
  }
  mkdirSync(dirname(linkPath), { recursive: true });
  symlinkSync(wanted, linkPath);
  return "created";
}

function installedPackageDirs() {
  const dirs = [];
  let topLevel = [];
  try {
    topLevel = readdirSync(modulesDir, { withFileTypes: true });
  } catch {
    return dirs;
  }
  for (const entry of topLevel) {
    if (entry.name.startsWith(".")) continue;
    if (!entry.isDirectory() && !entry.isSymbolicLink()) continue;
    if (!entry.name.startsWith("@")) {
      dirs.push(join(modulesDir, entry.name));
      continue;
    }
    let scoped = [];
    try {
      scoped = readdirSync(join(modulesDir, entry.name), { withFileTypes: true });
    } catch {
      continue;
    }
    for (const child of scoped) {
      if (child.name.startsWith(".")) continue;
      dirs.push(join(modulesDir, entry.name, child.name));
    }
  }
  return dirs;
}

/** Only packages pi will load as extensions can need host-provided modules. */
function isExtensionPackage(dir) {
  try {
    const manifest = JSON.parse(readFileSync(join(dir, "package.json"), "utf8"));
    return Boolean(manifest.pi) && typeof manifest.pi === "object";
  } catch {
    return false;
  }
}

/** Does this file reference the specifier somewhere it survives to runtime? */
function referencesAtRuntime(text, spec) {
  const quoted = [`"${spec}`, `'${spec}`, `\`${spec}`];
  for (const rawLine of text.split("\n")) {
    const line = rawLine.trim();
    // Type-only positions are erased before Node ever resolves them.
    if (line.startsWith("//") || line.startsWith("*") || line.startsWith("/*")) continue;
    if (/^(import|export)\s+type\s/.test(line)) continue;
    if (quoted.some((needle) => line.includes(needle))) return true;
  }
  return false;
}

/** Which host-provided packages does this extension reference at runtime? */
function referencedSpecs(packageDir) {
  const found = new Set();
  const stack = [packageDir];
  let files = 0;
  let bytes = 0;

  while (stack.length > 0 && files < SCAN_MAX_FILES && bytes < SCAN_MAX_TOTAL_BYTES) {
    const dir = stack.pop();
    let entries = [];
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === "node_modules" || entry.name === ".git") continue;
        stack.push(path);
        continue;
      }
      if (!entry.isFile()) continue;
      const dot = entry.name.lastIndexOf(".");
      if (dot < 0 || !SCAN_EXTENSIONS.has(entry.name.slice(dot))) continue;
      // Ambient declarations only describe types.
      if (entry.name.endsWith(".d.ts")) continue;

      let stats;
      try {
        stats = statSync(path);
      } catch {
        continue;
      }
      if (stats.size > SCAN_MAX_FILE_BYTES) continue;
      files += 1;
      bytes += stats.size;

      let text;
      try {
        text = readFileSync(path, "utf8");
      } catch {
        continue;
      }
      for (const spec of SPECS) {
        if (found.has(spec)) continue;
        if (referencesAtRuntime(text, spec)) found.add(spec);
      }
      if (found.size === SPECS.length) return found;
    }
  }
  return found;
}

function readState() {
  try {
    const parsed = JSON.parse(readFileSync(statePath, "utf8"));
    if (parsed && typeof parsed === "object" && parsed.links && typeof parsed.links === "object") {
      return parsed;
    }
  } catch {
    /* missing or corrupt state is simply a cache miss */
  }
  return { version: 1, links: {} };
}

function writeState(links) {
  try {
    mkdirSync(projectDir, { recursive: true });
    writeFileSync(
      statePath,
      `${JSON.stringify({ version: 1, updated: new Date().toISOString(), links }, null, 2)}\n`,
      "utf8",
    );
  } catch (error) {
    log(`could not record state at ${statePath}: ${error.message}`);
  }
}

function removeLink(linkPath) {
  const stats = lstatOrNull(linkPath);
  if (!stats) return false;
  if (!stats.isSymbolicLink()) return false;
  unlinkSync(linkPath);
  try {
    // Only succeeds while the scope directory is otherwise empty.
    if (basename(dirname(linkPath)).startsWith("@")) {
      const scopeDir = dirname(linkPath);
      if (readdirSync(scopeDir).length === 0) rmSync(scopeDir, { recursive: true, force: true });
    }
  } catch {
    /* an empty-directory tidy-up is cosmetic */
  }
  return true;
}

function repair() {
  const state = readState();
  const recorded = Object.entries(state.links);
  const broken = recorded.filter(([linkPath, target]) => !isValidLink(linkPath, target));

  if (!FULL && recorded.length > 0 && broken.length === 0) {
    log(`${recorded.length} recorded link(s) intact; nothing to do`);
    return { changed: 0, broken: 0, missingSources: [], recorded: recorded.length };
  }

  if (broken.length > 0) {
    log(`npm removed ${broken.length} of ${recorded.length} recorded link(s); rescanning`);
  } else if (recorded.length === 0) {
    log(`no recorded links yet; scanning ${modulesDir}`);
  }

  const sources = new Map();
  const sourceFor = (spec) => {
    if (!sources.has(spec)) sources.set(spec, findHostSource(spec));
    return sources.get(spec);
  };

  const links = {};
  const missingSources = new Set();
  let changed = 0;

  for (const packageDir of installedPackageDirs()) {
    if (!isExtensionPackage(packageDir)) continue;
    for (const spec of referencedSpecs(packageDir)) {
      const source = sourceFor(spec);
      if (!source) {
        missingSources.add(spec);
        continue;
      }
      for (const linkPath of [join(modulesDir, spec), join(packageDir, "node_modules", spec)]) {
        if (ensureLink(linkPath, source) === "created") changed += 1;
        links[linkPath] = realOrNull(source);
      }
    }
  }

  // Drop links that earlier scans created for references that no longer exist.
  let removed = 0;
  for (const linkPath of Object.keys(state.links)) {
    if (links[linkPath]) continue;
    if (removeLink(linkPath)) removed += 1;
  }

  writeState(links);
  log(`repaired ${changed} link(s), removed ${removed}; tracking ${Object.keys(links).length}`);
  return { changed, broken: broken.length, missingSources: [...missingSources], recorded: Object.keys(links).length };
}

try {
  if (!isDirectory(modulesDir)) {
    log(`no extension modules at ${modulesDir}; nothing to do`);
    process.exit(0);
  }
  const result = repair();
  if (CHECK) {
    if (result.missingSources.length > 0) {
      process.stderr.write(`pi-host-links: no host copy found for ${result.missingSources.join(", ")}\n`);
    }
    process.exit(result.changed > 0 || result.missingSources.length > 0 ? 1 : 0);
  }
} catch (error) {
  // Never block pi or npm: report and let the caller continue.
  process.stderr.write(`pi-host-links: ${error?.message ?? error}\n`);
  process.exit(CHECK ? 1 : 0);
}

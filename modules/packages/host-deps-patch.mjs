#!/usr/bin/env node
// Re-applies the "host-provided dependency" fix to installed pi extension packages.
//
// pi's resource loader warns when an extension package lists a host-provided
// package (pi-ai, pi-agent-core, pi-coding-agent, pi-tui, @sinclair/typebox,
// typebox) in `dependencies` instead of `peerDependencies: "*"`, because a
// physical copy can bypass pi's extension module mapping.
//
// npm install/uninstall rewrite these manifests from the registry, so this
// script is re-run after every pi package operation. Idempotent; silent.
//
// Usage: node host-deps-patch.mjs [node_modules_dir]

import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const HOST_PROVIDED = new Set([
  "@earendil-works/pi-agent-core",
  "@earendil-works/pi-ai",
  "@earendil-works/pi-coding-agent",
  "@earendil-works/pi-tui",
  "@mariozechner/pi-agent-core",
  "@mariozechner/pi-ai",
  "@mariozechner/pi-coding-agent",
  "@mariozechner/pi-tui",
  "@sinclair/typebox",
  "typebox",
]);

const positional = process.argv.slice(2).filter((arg) => !arg.startsWith("--"));
const root = positional[0] ?? join(homedir(), ".pi/agent/npm/node_modules");

/** Collect candidate package.json paths: node_modules/<pkg> and node_modules/@scope/<pkg>. */
function candidates(dir) {
  const out = [];
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory() && !entry.isSymbolicLink()) continue;
    if (entry.name === ".bin" || entry.name === ".package-lock.json") continue;
    if (entry.name.startsWith("@")) {
      const scopeDir = join(dir, entry.name);
      if (!existsSync(scopeDir)) continue;
      for (const sub of readdirSync(scopeDir, { withFileTypes: true })) {
        if (sub.isDirectory() || sub.isSymbolicLink()) {
          out.push(join(scopeDir, sub.name, "package.json"));
        }
      }
      continue;
    }
    out.push(join(dir, entry.name, "package.json"));
  }
  return out;
}

let patched = 0;
for (const path of candidates(root)) {
  if (!existsSync(path)) continue;
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(path, "utf-8"));
  } catch {
    continue;
  }
  // Only touch real extension packages; the warning targets extension package roots.
  if (!manifest?.pi?.extensions) continue;
  const deps = manifest.dependencies;
  if (!deps || typeof deps !== "object" || Array.isArray(deps)) continue;
  const offenders = Object.keys(deps).filter((name) => HOST_PROVIDED.has(name));
  if (offenders.length === 0) continue;

  const peers = manifest.peerDependencies && typeof manifest.peerDependencies === "object"
    ? manifest.peerDependencies
    : (manifest.peerDependencies = {});
  for (const name of offenders) {
    delete deps[name];
    if (!(name in peers)) peers[name] = "*";
  }
  writeFileSync(path, JSON.stringify(manifest, null, 2) + "\n", "utf-8");
  patched++;
}

if (process.argv.includes("--verbose")) {
  process.stderr.write(`host-deps-patch: patched ${patched} manifest(s) under ${root}\n`);
}

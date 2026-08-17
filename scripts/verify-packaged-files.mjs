#!/usr/bin/env node
//
// Everything the CLI reads at runtime must be in the published tarball.
//
// `files` is an allowlist, so a new directory is silently absent from the package
// until someone adds it — and the failure only shows up for whoever installs it,
// never for anyone running from a checkout.

import { execFileSync } from "node:child_process"
import { readdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")

// Read at runtime by bin/plans.mjs, by the libexec scripts, or by `init --docs`.
const RUNTIME_DIRS = ["bin", "lib", "libexec", "docs"]

const packed = new Set(
  JSON.parse(
    execFileSync("npm", ["pack", "--dry-run", "--json"], {
      cwd: root,
      encoding: "utf8",
    }),
  )[0].files.map(f => f.path),
)

const missing = []
for (const dir of RUNTIME_DIRS) {
  for (const entry of readdirSync(join(root, dir))) {
    if (!packed.has(`${dir}/${entry}`)) missing.push(`${dir}/${entry}`)
  }
}

if (missing.length > 0) {
  console.error("Runtime files missing from the published tarball:")
  for (const path of missing) console.error(`  ✗ ${path}`)
  console.error("\nAdd the directory to `files` in package.json.")
  process.exit(1)
}

console.log(`✓ ${packed.size} files packed, every runtime path included`)

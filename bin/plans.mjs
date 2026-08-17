#!/usr/bin/env node
//
// Dispatch a subcommand to its script in libexec/.
//
// The implementation is bash because the work is all low-level git commands —
// hash-object, write-tree, update-ref. This shim exists so the package still
// installs as an ordinary npm bin on every platform.

import { spawnSync } from "node:child_process"
import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { COMMANDS, MULTIPLEXED, USAGE } from "../lib/commands.mjs"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")

const [command, ...args] = process.argv.slice(2)

if (
  !command ||
  command === "--help" ||
  command === "-h" ||
  command === "help"
) {
  process.stdout.write(USAGE)
  process.exit(command ? 0 : 2)
}

if (command === "--version" || command === "-v") {
  const { version } = JSON.parse(
    readFileSync(join(root, "package.json"), "utf8"),
  )
  process.stdout.write(`${version}\n`)
  process.exit(0)
}

const script = COMMANDS[command]
if (!script) {
  process.stderr.write(`❌ Unknown command: ${command}\n\n${USAGE}`)
  process.exit(2)
}

// One script serves several commands, so it needs to know which one was asked for.
const argv = script === MULTIPLEXED ? [command, ...args] : args

const result = spawnSync("bash", [join(root, "libexec", script), ...argv], {
  stdio: "inherit",
})

if (result.error) {
  const reason =
    result.error.code === "ENOENT"
      ? "bash was not found on PATH. On Windows, run from Git Bash."
      : result.error.message
  process.stderr.write(`❌ Could not run plans ${command}: ${reason}\n`)
  process.exit(1)
}

process.exit(result.status ?? 1)

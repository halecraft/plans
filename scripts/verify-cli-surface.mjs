#!/usr/bin/env node
//
// The CLI surface is a four-way claim: a command exists, a script implements it,
// the usage text mentions it, and the README documents it. Nothing else holds
// those together — a script added without a dispatch entry is dead code, and a
// dispatch entry without a script is a runtime crash on a path tests may not cover.

import { readdirSync, readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { COMMANDS, MULTIPLEXED, USAGE } from "../lib/commands.mjs"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const problems = []

const commands = Object.keys(COMMANDS)
const dispatched = new Set(Object.values(COMMANDS))

// common.sh is a library the entry scripts source, not a command.
const onDisk = readdirSync(join(root, "libexec")).filter(
  f => f.endsWith(".sh") && f !== "common.sh",
)

for (const script of dispatched) {
  if (!onDisk.includes(script)) {
    problems.push(
      `COMMANDS dispatches to libexec/${script}, which does not exist`,
    )
  }
}

for (const script of onDisk) {
  if (!dispatched.has(script)) {
    problems.push(`libexec/${script} exists but no command dispatches to it`)
  }
}

if (!dispatched.has(MULTIPLEXED)) {
  problems.push(
    `MULTIPLEXED names ${MULTIPLEXED}, which no command dispatches to`,
  )
}

for (const command of commands) {
  // Usage lists one command per line, indented — not merely mentioned in prose.
  if (!new RegExp(`^ {2}${command}\\b`, "m").test(USAGE)) {
    problems.push(
      `\`${command}\` is dispatched but missing from the usage text`,
    )
  }
}

const readme = readFileSync(join(root, "README.md"), "utf8")
for (const command of commands) {
  if (!new RegExp(`\\|\\s*\`plans ${command}\\b`).test(readme)) {
    problems.push(
      `\`${command}\` is dispatched but missing from the README command table`,
    )
  }
}

if (problems.length > 0) {
  console.error("CLI surface is inconsistent:")
  for (const problem of problems) console.error(`  ✗ ${problem}`)
  process.exit(1)
}

console.log(
  `✓ ${commands.length} commands: dispatched, implemented, documented`,
)

// The CLI's surface, declared once.
//
// bin/ dispatches from this map; scripts/verify-cli-surface.mjs checks it against
// the scripts actually on disk, the usage text, and the README table. Keeping it
// here rather than in bin/ means the check reads the real thing instead of
// re-deriving it from source text.

export const COMMANDS = {
  init: "init.sh",
  add: "add.sh",
  sync: "sync.sh",
  status: "status.sh",
  list: "read.sh",
  show: "read.sh",
  grep: "read.sh",
}

// read.sh serves several commands, so it is told which one was asked for.
export const MULTIPLEXED = "read.sh"

export const USAGE = `plans — permanent plan documents in a git ref namespace

usage: plans <command> [args]

  init [--docs] [--autolink]   configure this repo to fetch and reflog the store
  add <file> [--as <slug>]     record a plan; the slug is its permanent ID
  sync [remote]                fetch, reconcile, publish the store and its mirror
  status [--fetch]             what is stored, what is unpublished

  list                         every plan in the store
  show <slug>                  print one plan
  grep <pattern>               search across every plan

Configure placement with git config: plans.ref, plans.remote, plans.mirrorBranch.
`

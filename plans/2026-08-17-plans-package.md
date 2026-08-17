# The two-part plan record, as an installable package

## Why

A plan document explains why a change is shaped the way it is — the phases, the
tests, the rejected alternatives. It is the most valuable artifact of a change
and the first one lost, because there is nowhere good to put it. In a commit
message it is too long to skim. In the working tree it goes stale the day it
ships, and every reader afterwards has to guess whether it still describes the
code.

The two-part record splits it by audience instead of by size. A short commit
message carries what a reader who will *never* open the plan must know. The full
document goes into a git ref namespace of its own, addressed by a stable slug
that the message names as `PLAN-YYYY-MM-DD-slug`. The plan is permanently in git,
never checked out, and one line of the commit message is the whole coupling.

This worked as two shell scripts in one repo. This package makes it installable.

## What ships

`@halecraft/plans`, an npm package with a `plans` bin. Seven commands: `init`,
`add`, `sync`, `status`, `list`, `show`, `grep`.

## Decisions

### npm distributes it; bash implements it

The work is pure git plumbing — `hash-object`, `read-tree`, `write-tree`,
`commit-tree`, `update-ref`. Bash is the right language for that; a TypeScript
port would be twice the length in `execFileSync("git", [...])` and read worse.

What the scripts lacked was a way to reach a second repo. That is a packaging
problem, not a language problem, so npm is the distribution channel and the
implementation stays as it was. `bin/plans.mjs` is a ~40-line dispatcher that
exists only because npm's guidance is that bin targets start with
`#!/usr/bin/env node`. No build step, no `dist/`.

### The plan ID is not configurable

Plans are addressed as `YYYY-MM-DD-slug`, enforced on the way in. This is the one
thing an adopting repo cannot change, because it is doing three jobs:

- **Distributed minting.** A date anyone can read off a calendar means two people,
  offline, on different branches, mint non-colliding IDs with no central counter.
- **Disjoint merges.** Every plan is its own path, so concurrent additions are
  disjoint additions and the stores merge with no force-push. A stack position or
  an incrementing number collides immediately and takes that guarantee with it.
- **Legibility.** The date is readable at a glance.

The second point is why this is a hard constraint rather than a default. The
merge guarantee is a property of the naming scheme; making the scheme a
preference would silently remove it.

A draft filename is a *different namespace* from the plan ID — a stack position
is local and ephemeral, the ID is permanent once pushed. So `add` takes `--as` to
mint explicitly, and on a non-conforming name it prints the mint command rather
than guessing. The ID cannot be retracted once published, so it is never inferred.

### The store and its mirror move together

The store lives at `refs/plans/store`; a mirror branch holds the same tree so
plans are browsable on the web and a `PLAN-` autolink has something to resolve
against.

Publishing them separately is the failure this package exists to prevent. In the
repo where the technique was invented, the sync script pushed the store and left
the mirror to a manual command documented only in prose. The mirror was pushed
once and then never again: the store advanced by 38 plans over three and a half
weeks while every web link silently resolved to an older tree, and nothing
reported it. Local reads kept working, so there was no symptom.

So `sync` publishes both, and it evaluates the mirror even when the store needs
no push — the stale-mirror case is exactly the one a "nothing to do" early exit
skips. `status` reports the drift explicitly.

### `init` is a command, not a postinstall hook

Setup writes to the user's git config: a fetch refspec for the store, and
`core.logAllRefUpdates always` so a ref move stays recoverable. An install should
not do that behind someone's back, so it is an explicit command.

### Host-specific help is printed, not performed

GitHub can turn a `PLAN-` token into a clickable link, through a per-repository
rule it calls an autolink. An earlier version of `init` created that rule for you
by shelling out to the `gh` CLI.

That was wrong three ways. It changed someone's repository settings from inside a
setup command. It needed admin rights the tool cannot check for. And when the API
refused, a wrapper could only report *that* it refused, not why — so a user on a
host without the feature got the same shrug as one who merely lacked permission.
It was also host-blind: it aimed at github.com no matter where the repo actually
pushes, which on an unlucky name collision would have configured a stranger's
repository.

So `init` prints the exact command instead, and only when the remote really is
GitHub. The package now has no external CLI dependency at all — git, bash, node.

## What is configurable

Read from git config, so placement moves without editing anything: `plans.ref`,
`plans.remote`, `plans.mirrorBranch` (empty disables the mirror). The plan ID
format is not among them, per above.

## Verification

`test/smoke.sh` runs every command against a throwaway repo and a bare remote.
The invariant it guards hardest is the premise: recording a plan must leave the
working tree, the index, and HEAD untouched, and the store must sit on no branch.

Beyond that it covers the branches that are easy to get wrong and hard to notice:
two peers adding plans concurrently must merge cleanly, the same ID claimed twice
must refuse without publishing, a stale mirror must be repaired even when the
store is current, and an earlier revision must stay recoverable after a plan is
revised.

`verify.config.ts` adds shellcheck at `style` severity — the only static analysis
shell gets — plus two structural checks: that every command is dispatched,
implemented and documented, and that every runtime directory is in the published
tarball. Both guard claims no test would fail on.

## Rejected

**A `jj plan` subcommand.** The store needs only git, and binding it to jj would
narrow it for no gain. The two-part record composes with any git repo.

**Porting the scripts to TypeScript.** See above — it would lengthen the code and
obscure it, to solve a distribution problem that packaging already solves.

**Making the ID format configurable.** It reads as a courtesy to adopting repos
and silently removes the merge guarantee.

## Open

- The browse link `init --docs` writes into `docs/plans.md` is still a github.com
  URL whatever the remote's host, which is simply wrong anywhere else. `init` now
  parses the host, so the fix is small — emit the link only for hosts whose URL
  shape we know, or accept an explicit override.
- The concurrent-merge tests need git 2.38 for `merge-tree --write-tree`. On
  older git they fail rather than skip, though `sync` itself explains why.

# @halecraft/plans

> Keep plans in git, permanently, without treating them as regular tracked files.

I think plan documents are the most valuable part of a change, because they document what the developer(s) and designer(s) were thinking at the time of implementation. But we often don't keep them around, usually for fear they'll lose relevance and become noise over time.

This tool makes it easy to track those files in git, but within a separate git ref namespace. This brings all of the benefits of git-tracked plans with none of the atrophy or pollution downsides.

`@halecraft/plans` stores plans in a git ref namespace `refs/plans/store`. They are genuinely in git and permanently recorded, but they are never checked out. The commit that implements a plan carries a short `PLAN-YYYY-MM-DD-slug` reference to it.

```bash
plans add .plans/2026-07-23-tts-timed-tokens.md   # local, offline, instant
plans sync                                        # publish, whenever
plans show PLAN-2026-07-23-tts-timed-tokens       # read it back, years later
```

## Install

```bash
pnpm add -D @halecraft/plans
pnpm exec plans init
```

`init` adds a fetch refspec for the store and turns on `core.logAllRefUpdates`, so a ref move you regret stays recoverable. It is a command rather than a postinstall hook on purpose — an install should not write to your git config behind your back.

Add `--docs` to drop a `docs/plans.md` into the repo explaining the workflow to everyone else, and `--autolink` to register the `PLAN-` autolink on GitHub (needs `gh` and admin rights).

Drafts are ordinary files until you record them, so keep the directory you author in out of the repo:

```bash
echo .plans/ >> .gitignore
```

## Commands

|  |  |
| --- | --- |
| `plans init [--docs] [--autolink]` | configure this repo |
| `plans add <file> [--as <slug>]` | record a plan; the slug is its permanent ID |
| `plans sync [remote]` | fetch, reconcile, publish the store and its mirror |
| `plans status [--fetch]` | what is stored, what is unpublished |
| `plans list` | every plan in the store |
| `plans show <slug>` | print one plan (accepts a `PLAN-` token) |
| `plans grep <pattern>` | search across every plan |

## The plan ID

Plans are addressed as `YYYY-MM-DD-slug`, and that shape is enforced, not configurable. It is doing three jobs at once:

- **Distributed ID minting.** A date anyone can read off a calendar means two people, offline, on different branches, mint non-colliding IDs with no central counter.
- **Disjoint merges.** Because every plan is its own path, two people adding plans concurrently produce disjoint additions — the store merges cleanly with no force-push. A looser scheme (a stack position, an incrementing number) collides immediately and takes that guarantee with it.
- **Legibility.** You can date a plan at a glance.

If your draft is named something else — a PR stack position like `01-feat-auth.md`, a change id — the draft name and the plan ID are simply different namespaces. The draft name is local and ephemeral; the ID is permanent once pushed. So mint it explicitly:

```bash
plans add .plans/01-feat-auth.md --as 2026-07-23-feat-auth
```

Running `add` without `--as` on a non-conforming name prints the mint command, ready to paste. It never guesses on your behalf, because the ID cannot be retracted once published.

## Referencing a plan from a commit

`plans add` records the document; you write the reference. Put the plan ID on its own line at the end of the commit message, prefixed with `PLAN-`:

```
feat(app-core): the tutor's own timeline

The token map is now read by the projection fold, in one place.

PLAN-2026-07-23-tts-timed-tokens
```

That line is the whole coupling. The message stays short for anyone skimming `git log`, and `plans show PLAN-2026-07-23-tts-timed-tokens` resolves it back to the full document — as does a click, if you registered the autolink.

Split the two by audience rather than by size: the message carries what a reader who will *never* open the plan must know, and the plan carries what someone doing deliberate archaeology wants.

## How it works

`plans add` writes a blob, builds a tree with a dedicated index, and moves a ref. It never touches the working tree or the git index — so plans are recorded without ever appearing as tracked files, and without disturbing anything you have in progress. The ref move is a compare-and-swap, so a concurrent writer cannot be clobbered.

The namespace mirrors how branches work offline:

- `refs/plans/store` — local and authoritative
- `refs/plans/<remote>/store` — last-known state of the remote
- the `plans` branch — a plain projection of the store, so plans are browsable on the web and the `PLAN-` autolink has something to resolve against

`plans sync` behaves much as `git pull` then `git push`: fast-forward when you are behind, push when you are ahead, merge when both happened. **The store and its mirror always move together**, so "published" has one meaning — a store that is current while its mirror lags is invisible drift, where local reads work but every web link silently resolves to an older tree. `plans status` reports that state explicitly.

Re-adding an edited plan records a revision rather than replacing it. The store's history is append-only, so earlier versions stay recoverable:

```bash
git log --oneline refs/plans/store -- plans/2026-07-23-tts-timed-tokens.md
git show <sha>:plans/2026-07-23-tts-timed-tokens.md
```

Because the ID is a slug and not a content hash, revising a plan leaves every commit that references it correct as written.

## Configuration

Read from git config, so an adopting repo can move the store without editing anything:

| key | default |  |
| --- | --- | --- |
| `plans.ref` | `refs/plans/store` | where the store lives |
| `plans.remote` | `origin` | which remote to publish to |
| `plans.mirrorBranch` | `plans` | the web-browsable projection; set empty to disable |

The plan ID format is not configurable — see above for why.

## Requirements

Node 18+, git 2.20+ (2.38+ for the divergence merge path), and bash. On Windows, run from Git Bash.

## One property to respect

A **pushed** plan is permanent, exactly like a pushed commit. Deleting the ref removes reachability, not the objects — a host will still serve one to anyone who knows its SHA. Don't put a live credential in a plan you intend to push; working notes are the most likely place one slips in.

## Development

```bash
pnpm install
pnpm verify       # format, shellcheck, CLI-surface and packaging checks, smoke test
pnpm verify:fix   # apply formatting fixes
```

`pnpm test` runs the smoke test alone. It exercises every command against a throwaway repo and a bare remote, and asserts the invariant the design rests on — that recording a plan leaves the working tree and the index untouched.

## License

MIT

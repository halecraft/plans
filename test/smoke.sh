#!/usr/bin/env bash
#
# End-to-end smoke test against a throwaway repo and a bare "remote".
#
# The invariant worth guarding hardest is the last one: adding a plan must leave
# the working tree and the index untouched, or the whole premise is broken.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PLANS="node $ROOT/bin/plans.mjs"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

ok() {
	pass=$((pass + 1))
	printf '  ✅ %s\n' "$1"
}

no() {
	fail=$((fail + 1))
	printf '  ❌ %s\n' "$1"
	[ -n "${2:-}" ] && printf '     %s\n' "$2"
}

assert_contains() {
	case $2 in
	*"$3"*) ok "$1" ;;
	*) no "$1" "expected to find: $3" ;;
	esac
}

assert_eq() {
	if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "got '$2', want '$3'"; fi
}

# --- fixture -----------------------------------------------------------------

git init --bare -q "$tmp/remote.git"
git init -q "$tmp/repo"
cd "$tmp/repo"
git config user.email test@example.com
git config user.name Test
git remote add origin "$tmp/remote.git"
echo hello >README.md
git add README.md
git commit -qm "initial"
git push -q origin HEAD

mkdir -p drafts
printf '# Timed tokens\n\nDeepgram gives us word timings.\n' >drafts/2026-07-23-tts-timed-tokens.md
printf '# Feat auth\n\nExtract the auth module.\n' >drafts/a-01-feat-auth.md
printf '# Bare position\n' >drafts/01-bare-position.md
printf '# Change id\n' >drafts/335d3058-from-change-id.md

# --- init --------------------------------------------------------------------

echo "init"
$PLANS init >/dev/null
assert_eq "adds the fetch refspec" \
	"$(git config --get-all remote.origin.fetch | grep -c 'refs/plans')" "1"
assert_eq "reflogs the namespace" "$(git config --get core.logAllRefUpdates)" "always"
out=$($PLANS init)
assert_eq "is idempotent" \
	"$(git config --get-all remote.origin.fetch | grep -c 'refs/plans')" "1"

# Host-specific advice is offered only where the feature exists.
if printf '%s' "$out" | grep -q "clickable on GitHub"; then
	no "stays quiet about GitHub on another host" "it offered the autolink anyway"
else
	ok "stays quiet about GitHub on another host"
fi

git init -q "$tmp/gh"
git -C "$tmp/gh" remote add origin git@github.com:acme/widgets.git
out=$(cd "$tmp/gh" && $PLANS init)
assert_contains "offers the autolink command on GitHub" "$out" "gh api repos/acme/widgets/autolinks"
assert_contains "aims the autolink at the mirror" "$out" "blob/plans/plans/<num>.md"

# Remote URLs come in several shapes; owner/repo has to survive all of them.
git init -q "$tmp/ssh"
git -C "$tmp/ssh" remote add origin ssh://code.example.org:29418/acme/widgets.git
(cd "$tmp/ssh" && $PLANS init --docs >/dev/null)
assert_contains "parses a user-less ssh url with a port" \
	"$(grep 'browsed on the web' "$tmp/ssh/docs/plans.md")" "acme/widgets/tree/plans"

# --- add ---------------------------------------------------------------------

echo "add"
out=$($PLANS add drafts/2026-07-23-tts-timed-tokens.md)
assert_contains "creates the store" "$out" "Created store with plans/2026-07-23-tts-timed-tokens.md"
assert_contains "prints the PLAN- reference" "$out" "PLAN-2026-07-23-tts-timed-tokens"

out=$($PLANS add drafts/2026-07-23-tts-timed-tokens.md)
assert_contains "re-adding unchanged is a no-op" "$out" "Already stored and unchanged"

if out=$($PLANS add drafts/a-01-feat-auth.md 2>&1); then
	no "refuses a non-conforming draft name" "it succeeded"
else
	assert_contains "refuses a non-conforming draft name" "$out" "Not a plan ID"
	assert_contains "suggests an explicit mint" "$out" "--as $(date +%Y-%m-%d)-feat-auth"
fi

# The suggestion strips however the draft addressed itself, so the minted ID is
# the plan's own name rather than a stack position carried over.
for case in "01-bare-position:bare-position" "335d3058-from-change-id:from-change-id"; do
	draft=${case%%:*}
	out=$($PLANS add "drafts/$draft.md" 2>&1 || true)
	assert_contains "strips the prefix from $draft" "$out" "--as $(date +%Y-%m-%d)-${case##*:}"
done

if out=$($PLANS add drafts/a-01-feat-auth.md --as nonsense 2>&1); then
	no "rejects a malformed --as slug" "it succeeded"
else
	assert_contains "rejects a malformed --as slug" "$out" "Not a plan ID"
fi

out=$($PLANS add drafts/a-01-feat-auth.md --as 2026-07-24-feat-auth)
assert_contains "mints via --as" "$out" "Stored plans/2026-07-24-feat-auth.md"

# --- the invariant -----------------------------------------------------------

echo "isolation"
assert_eq "working tree is untouched" "$(git status --porcelain -- ':!drafts')" ""
assert_eq "HEAD is untouched" "$(git rev-list --count HEAD)" "1"
assert_eq "the store is not on any branch" \
	"$(git branch --contains refs/plans/store 2>/dev/null | wc -l | tr -d ' ')" "0"

# --- read --------------------------------------------------------------------

echo "read"
assert_eq "lists both plans" "$($PLANS list | wc -l | tr -d ' ')" "2"
assert_contains "shows a plan" "$($PLANS show 2026-07-23-tts-timed-tokens)" "Deepgram gives us"
assert_contains "accepts a PLAN- token" "$($PLANS show PLAN-2026-07-24-feat-auth)" "Extract the auth"
assert_contains "greps across plans" "$($PLANS grep Deepgram)" "2026-07-23-tts-timed-tokens"
assert_contains "reports no matches cleanly" "$($PLANS grep zzzznotfound)" "(no matches)"

if out=$($PLANS show 2026-01-01-nope 2>&1); then
	no "errors on a missing plan" "it succeeded"
else
	assert_contains "errors on a missing plan" "$out" "No such plan"
fi

# --- status before publishing ------------------------------------------------

echo "status"
out=$($PLANS status)
assert_contains "reports nothing published" "$out" "Nothing published yet"

# --- sync --------------------------------------------------------------------

echo "sync"
out=$($PLANS sync)
assert_contains "publishes the store" "$out" "Published"
assert_contains "updates the mirror" "$out" "Updating the plans mirror"

assert_eq "store is on the remote" \
	"$(git --git-dir="$tmp/remote.git" rev-parse --verify -q refs/plans/store >/dev/null && echo yes)" "yes"
# A missing mirror reads as an empty sha here, so this covers its existence too.
assert_eq "mirror matches the store" \
	"$(git --git-dir="$tmp/remote.git" rev-parse -q --verify refs/heads/plans)" \
	"$(git rev-parse refs/plans/store)"

out=$($PLANS status)
assert_contains "reports a clean state" "$out" "Everything published"

# --- a stale mirror is caught ------------------------------------------------

echo "drift"
git --git-dir="$tmp/remote.git" update-ref -d refs/heads/plans
git update-ref -d refs/remotes/origin/plans 2>/dev/null || true
out=$($PLANS status)
assert_contains "notices a missing mirror" "$out" "not browsable on the web"

# The store needs no push here, so a sync that stopped at "already in sync" would
# leave the mirror gone and report success. Publishing has to mean both refs.
$PLANS sync >/dev/null
assert_eq "restores a stale mirror even when the store needs no push" \
	"$(git --git-dir="$tmp/remote.git" rev-parse -q --verify refs/heads/plans)" \
	"$(git rev-parse refs/plans/store)"

printf '# Timed tokens\n\nSoniox gives us word timings.\n' >drafts/2026-07-23-tts-timed-tokens.md
$PLANS add drafts/2026-07-23-tts-timed-tokens.md >/dev/null
out=$($PLANS status)
assert_contains "notices unpublished revisions" "$out" "unpublished"
assert_contains "names the unpublished plan" "$out" "2026-07-23-tts-timed-tokens"

$PLANS sync >/dev/null
out=$($PLANS status)
assert_contains "sync restores both refs" "$out" "Everything published"
assert_contains "revision is readable" "$($PLANS show 2026-07-23-tts-timed-tokens)" "Soniox"
assert_eq "revision did not add a plan" "$($PLANS list | wc -l | tr -d ' ')" "2"

# The store is append-only, so the version a commit was written against survives.
first=$(git log --format=%H refs/plans/store -- plans/2026-07-23-tts-timed-tokens.md | tail -1)
assert_contains "an earlier revision stays recoverable" \
	"$(git show "$first:plans/2026-07-23-tts-timed-tokens.md")" "Deepgram"

# --- second clone ------------------------------------------------------------

echo "adopt"
git clone -q "$tmp/remote.git" "$tmp/clone"
cd "$tmp/clone"
git config user.email test@example.com
git config user.name Test
$PLANS init >/dev/null
$PLANS sync >/dev/null
assert_eq "a fresh clone adopts the store" "$($PLANS list | wc -l | tr -d ' ')" "2"

# --- two people at once ------------------------------------------------------

# The whole reason the plan ID is a date plus a slug: two peers adding plans at the
# same time write different paths, so the stores merge with no force-push. This is
# the branch that claim rests on, and it needs git 2.38+ for merge-tree.

echo "concurrent"
cd "$tmp/clone"
printf '# From the clone\n' >clone-plan.md
$PLANS add clone-plan.md --as 2026-07-26-from-the-clone >/dev/null
$PLANS sync >/dev/null

cd "$tmp/repo"
printf '# From the first repo\n' >drafts/2026-07-26-from-the-repo.md
$PLANS add drafts/2026-07-26-from-the-repo.md >/dev/null
out=$($PLANS sync)
assert_contains "merges a diverged store" "$out" "Diverged"
assert_eq "keeps both concurrent plans" "$($PLANS list | wc -l | tr -d ' ')" "4"
assert_eq "the mirror follows a merge" \
	"$(git --git-dir="$tmp/remote.git" rev-parse -q --verify refs/heads/plans)" \
	"$(git rev-parse refs/plans/store)"

# The one case that has to stop: the same ID claimed twice with different content.
cd "$tmp/clone"
$PLANS sync >/dev/null
printf '# The clone got there first\n' >clash.md
$PLANS add clash.md --as 2026-07-27-same-day-clash >/dev/null
$PLANS sync >/dev/null

cd "$tmp/repo"
printf '# Different content, same ID\n' >drafts/2026-07-27-same-day-clash.md
$PLANS add drafts/2026-07-27-same-day-clash.md >/dev/null
if out=$($PLANS sync 2>&1); then
	no "refuses two plans claiming the same ID" "it succeeded"
else
	assert_contains "refuses two plans claiming the same ID" "$out" "Conflicting plans"
	assert_contains "names the clashing plan" "$out" "2026-07-27-same-day-clash"
fi
assert_eq "leaves the published store untouched on conflict" \
	"$(git --git-dir="$tmp/remote.git" rev-parse refs/plans/store)" \
	"$(git rev-parse refs/plans/origin/store)"

# --- docs template -----------------------------------------------------------

echo "docs"
cd "$tmp/repo"
$PLANS init --docs >/dev/null
assert_contains "writes the docs template" "$(cat docs/plans.md)" "# Plan Documents"
assert_eq "leaves no placeholder behind" "$(grep -c '{{' docs/plans.md || true)" "0"
out=$($PLANS init --docs)
assert_contains "never overwrites an existing doc" "$out" "already exists"

# --- configurable placement --------------------------------------------------

echo "config"
git init -q "$tmp/custom"
cd "$tmp/custom"
git config user.email test@example.com
git config user.name Test
git remote add upstream "$tmp/remote2.git"
git init --bare -q "$tmp/remote2.git"
git config plans.ref refs/design/store
git config plans.remote upstream
git config plans.mirrorBranch ""
printf '# Custom\n' >plan.md

$PLANS init >/dev/null
assert_eq "honours plans.ref and plans.remote" \
	"$(git config --get-all remote.upstream.fetch | grep -c 'refs/design/store:refs/design/upstream/store')" "1"

$PLANS add plan.md --as 2026-07-25-custom-placement >/dev/null
assert_eq "stores under plans.ref" \
	"$(git rev-parse --verify -q refs/design/store >/dev/null && echo yes)" "yes"
assert_eq "leaves the default ref alone" \
	"$(git rev-parse --verify -q refs/plans/store >/dev/null || echo absent)" "absent"

out=$($PLANS sync)
assert_contains "publishes to plans.remote" "$out" "Published"
if printf '%s' "$out" | grep -q mirror; then
	no "an empty plans.mirrorBranch disables the mirror" "it still pushed one"
else
	ok "an empty plans.mirrorBranch disables the mirror"
fi
assert_eq "no mirror branch on the remote" \
	"$(git --git-dir="$tmp/remote2.git" for-each-ref refs/heads | wc -l | tr -d ' ')" "0"

out=$($PLANS status)
assert_contains "status is clean without a mirror" "$out" "Everything published"

# --- report ------------------------------------------------------------------

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

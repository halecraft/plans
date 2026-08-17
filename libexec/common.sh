#!/usr/bin/env bash
#
# Configuration and helpers shared by every subcommand.
#
# Where the store sits is read from git config, so an adopting repo can move it
# without editing scripts. The slug format is deliberately NOT configurable: it
# is the contract behind the PLAN- token, the GitHub autolink, and the
# disjoint-path merge that lets two people add plans offline without conflict.
#
# shellcheck disable=SC2034  # every value here is read by the scripts that source it.
set -euo pipefail

# Fixed by contract: the directory inside the store tree, and the plan ID shape.
STORE_DIR=plans
SLUG_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$'

die() {
	printf '❌ %s\n' "$*" >&2
	exit 1
}

git rev-parse --git-dir >/dev/null 2>&1 || die "Not a git repository."

STORE_REF=$(git config --get plans.ref || echo refs/plans/store)
REMOTE=$(git config --get plans.remote || echo origin)
MIRROR_BRANCH=$(git config --get plans.mirrorBranch || echo plans)

# Mirrors how branches work: the local ref is authoritative, and the tracking
# ref alongside it is the last-known state of the remote.
TRACK_REF="${STORE_REF%/*}/$REMOTE/${STORE_REF##*/}"

# git 2.38 introduced `merge-tree --write-tree`, which sync's divergence path uses.
git_at_least() {
	local have major minor
	have=$(git --version | sed -n 's/^git version \([0-9]*\)\.\([0-9]*\).*/\1 \2/p')
	major=${have%% *}
	minor=${have##* }
	[ "$major" -gt "$1" ] || { [ "$major" -eq "$1" ] && [ "$minor" -ge "$2" ]; }
}

plan_count() {
	git ls-tree -r --name-only "$1" 2>/dev/null | wc -l | tr -d ' '
}

# "1 plan" / "3 plans", so callers do not each re-solve the plural.
plans_phrase() {
	local count=$1
	if [ "$count" = 1 ]; then printf '1 plan'; else printf '%s plans' "$count"; fi
}

ref_exists() {
	git rev-parse --verify --quiet "$1" >/dev/null
}

# Turn a draft filename into a well-formed plan ID, for the `add` hint.
# Strips a stale date, a stack position (01-, a-01-), or a change id, then stamps
# today's — the draft name and the plan ID are different namespaces, and only the
# second one is permanent. The date goes first, so the year is never read as one.
suggest_slug() {
	local base=${1%.md}
	base=$(basename "$base")
	base=$(printf '%s' "$base" |
		sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//; s/^[a-z]-[0-9]+-//; s/^[0-9a-f]{7,}-//; s/^[0-9]+-//')
	base=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' |
		sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
	[ -n "$base" ] || base=plan
	printf '%s-%s' "$(date +%Y-%m-%d)" "$base"
}

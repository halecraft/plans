#!/usr/bin/env bash
#
# Publish and receive plan documents: fetch, fast-forward or merge, push.
#
# The store namespace mirrors how branches work — the local ref is authoritative,
# the tracking ref is the last-known state of the remote. Fetching only ever moves
# the tracking ref, so local work is never lost, and the remote enforces
# fast-forward on the store exactly as it does on a branch.
#
# Concurrent plans are always disjoint file additions (each plan has its own
# date+slug path), so a divergence merges cleanly without a force-push.
#
# Publishing also updates the mirror branch, which is what makes plans browsable
# on the web and what the PLAN- autolink resolves against. Store and mirror move
# together, so "published" has one meaning.
set -euo pipefail
# shellcheck source=libexec/common.sh
. "$(dirname "$0")/common.sh"

case ${1:-} in
-h | --help)
	echo "usage: plans sync [remote]" >&2
	exit 0
	;;
esac

# An explicit remote overrides plans.remote, and the tracking ref follows it.
if [ $# -gt 0 ]; then
	REMOTE=$1
	TRACK_REF="${STORE_REF%/*}/$REMOTE/${STORE_REF##*/}"
fi

# Publish the store tip to the mirror branch. The mirror is a pure projection of
# the store, so this is always a fast-forward unless someone committed to the
# branch directly.
sync_mirror() {
	[ -n "$MIRROR_BRANCH" ] || return 0

	echo "→ Updating the $MIRROR_BRANCH mirror on $REMOTE"
	if ! mirror_output=$(git push "$REMOTE" "$STORE_REF:refs/heads/$MIRROR_BRANCH" 2>&1); then
		printf '%s\n' "$mirror_output" | sed 's/^/  /' >&2
		echo "❌ Could not update the $MIRROR_BRANCH mirror." >&2
		echo "   It should only ever hold the store, so a rejection means something" >&2
		echo "   else was committed to that branch. Inspect it before overwriting." >&2
		exit 1
	fi
	printf '%s\n' "$mirror_output" | sed 's/^/  /'
}

# Fetch the refspec explicitly rather than relying on config, so this works in a
# fresh clone that has not been configured yet.
echo "→ Fetching plans from $REMOTE"
if fetch_output=$(git fetch "$REMOTE" "+$STORE_REF:$TRACK_REF" 2>&1); then
	if [ -n "$fetch_output" ]; then
		printf '%s\n' "$fetch_output" | sed 's/^/  /'
	fi
elif printf '%s' "$fetch_output" | grep -q "couldn't find remote ref"; then
	# The remote has no store yet — expected on the very first publish.
	echo "  (no plans on $REMOTE yet)"
else
	printf '%s\n' "$fetch_output" | sed 's/^/  /' >&2
	exit 1
fi

local_sha=$(git rev-parse --verify --quiet "$STORE_REF" || true)
track_sha=$(git rev-parse --verify --quiet "$TRACK_REF" || true)

if [ -z "$local_sha" ] && [ -z "$track_sha" ]; then
	echo "✅ No plans anywhere yet. Add one with: plans add <file>"
	exit 0
fi

if [ -z "$local_sha" ]; then
	git update-ref -m "plans sync: adopt $REMOTE" "$STORE_REF" "$track_sha"
	echo "✅ Adopted the remote store ($(git rev-parse --short "$STORE_REF"))"
	sync_mirror
	exit 0
fi

push_needed=true

if [ -n "$track_sha" ]; then
	if [ "$local_sha" = "$track_sha" ]; then
		echo "✅ Store already in sync ($(git rev-parse --short "$STORE_REF"))"
		push_needed=false
	elif git merge-base --is-ancestor "$local_sha" "$track_sha"; then
		git update-ref -m "plans sync: fast-forward from $REMOTE" "$STORE_REF" "$track_sha" "$local_sha"
		echo "✅ Fast-forwarded to $REMOTE ($(git rev-parse --short "$STORE_REF"))"
		push_needed=false
	elif git merge-base --is-ancestor "$track_sha" "$local_sha"; then
		echo "→ Local store is ahead; pushing"
	else
		echo "→ Diverged from $REMOTE; merging"
		git_at_least 2 38 ||
			die "Merging a diverged store needs git 2.38+ (you have $(git --version | awk '{print $3}'))."
		if ! merged_tree=$(git merge-tree --write-tree "$STORE_REF" "$TRACK_REF" 2>/dev/null); then
			echo "❌ Conflicting plans — the same path was written differently on both sides." >&2
			echo "   Rename your plan (the date+slug must be unique) and re-add it:" >&2
			{ git merge-tree --write-tree --name-only "$STORE_REF" "$TRACK_REF" 2>/dev/null || true; } |
				tail -n +2 | sed -n '/^$/q; s/^/     /p' >&2
			exit 1
		fi
		merge=$(git commit-tree "$merged_tree" -p "$local_sha" -p "$track_sha" -m "plans: merge $REMOTE")
		git update-ref -m "plans sync: merge $REMOTE" "$STORE_REF" "$merge" "$local_sha"
		echo "  merged ($(git rev-parse --short "$STORE_REF"))"
	fi
fi

if [ "$push_needed" = true ]; then
	echo "→ Pushing to $REMOTE"
	if ! git push "$REMOTE" "$STORE_REF:$STORE_REF" 2>&1 | sed 's/^/  /'; then
		echo "❌ Push rejected — someone else pushed in the meantime. Re-run to merge." >&2
		exit 1
	fi
	git update-ref "$TRACK_REF" "$(git rev-parse "$STORE_REF")"
	echo "✅ Published ($(git rev-parse --short "$STORE_REF"))"
fi

# Always, even when the store needed no push: the mirror can lag on its own, and
# a stale mirror is exactly the drift this is meant to prevent.
sync_mirror

echo "   $(plans_phrase "$(plan_count "$STORE_REF")") in the store"

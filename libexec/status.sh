#!/usr/bin/env bash
#
# Show what is stored locally, what is published, and what has drifted.
#
# Offline by default: it reads the tracking refs rather than the network, so it
# stays usable without credentials. Pass --fetch to refresh them first.
set -euo pipefail
# shellcheck source=libexec/common.sh
. "$(dirname "$0")/common.sh"

do_fetch=false
case ${1:-} in
--fetch) do_fetch=true ;;
-h | --help)
	echo "usage: plans status [--fetch]" >&2
	exit 0
	;;
"") ;;
*) die "Unknown option: $1" ;;
esac

MIRROR_REF="refs/remotes/$REMOTE/$MIRROR_BRANCH"

if [ "$do_fetch" = true ]; then
	echo "→ Fetching from $REMOTE"
	git fetch "$REMOTE" "+$STORE_REF:$TRACK_REF" 2>/dev/null || true
	if [ -n "$MIRROR_BRANCH" ]; then
		git fetch "$REMOTE" "+refs/heads/$MIRROR_BRANCH:$MIRROR_REF" 2>/dev/null || true
	fi
	echo
fi

row() {
	local label=$1 ref=$2
	if ref_exists "$ref"; then
		printf '%-8s %-26s %-9s %s\n' \
			"$label" "$ref" "$(git rev-parse --short "$ref")" "$(plans_phrase "$(plan_count "$ref")")"
	else
		printf '%-8s %-26s %s\n' "$label" "$ref" "—"
	fi
}

row "Store" "$STORE_REF"
row "Remote" "$TRACK_REF"
[ -n "$MIRROR_BRANCH" ] && row "Mirror" "$MIRROR_REF"
echo

if ! ref_exists "$STORE_REF"; then
	echo "No plans yet. Add one with: plans add <file>"
	exit 0
fi

store_sha=$(git rev-parse "$STORE_REF")
drifted=false

if ! ref_exists "$TRACK_REF"; then
	echo "⚠ Nothing published yet — the whole store is local-only."
	drifted=true
elif [ "$(git rev-parse "$TRACK_REF")" != "$store_sha" ]; then
	if git merge-base --is-ancestor "$TRACK_REF" "$STORE_REF"; then
		ahead=$(git rev-list --count "$TRACK_REF..$STORE_REF")
		changed=$(git diff --name-only "$TRACK_REF" "$STORE_REF" | sed "s|^$STORE_DIR/||; s|\.md$||")
		count=$(printf '%s\n' "$changed" | grep -c . || true)
		echo "⚠ $(plans_phrase "$count") unpublished ($ahead store commits ahead):"
		printf '%s\n' "$changed" | head -10 | sed 's/^/   /'
		[ "$count" -gt 10 ] && printf '   … and %s more\n' "$((count - 10))"
		drifted=true
	else
		echo "⚠ Local and remote stores have diverged — run: plans sync"
		drifted=true
	fi
fi

# A current store with a lagging mirror is invisible drift: local reads work,
# but every web link and PLAN- autolink still resolves to the older tree.
if [ -n "$MIRROR_BRANCH" ]; then
	if ! ref_exists "$MIRROR_REF"; then
		echo "⚠ No $MIRROR_BRANCH mirror on $REMOTE — plans are not browsable on the web."
		drifted=true
	elif [ "$(git rev-parse "$MIRROR_REF")" != "$store_sha" ]; then
		echo "⚠ The $MIRROR_BRANCH mirror lags the store — web links and PLAN- autolinks are stale."
		drifted=true
	fi
fi

if [ "$drifted" = true ]; then
	echo
	echo "   Publish with: plans sync"
else
	echo "✅ Everything published."
fi

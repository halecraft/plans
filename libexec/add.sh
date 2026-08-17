#!/usr/bin/env bash
#
# Record a plan document in the store ref namespace.
#
# Entirely local and offline: it writes a blob, builds a tree, and moves a ref.
# The working tree and the git index are both untouched — plans are permanently
# recorded without ever appearing as tracked files.
#
# Publish with `plans sync`.
set -euo pipefail
# shellcheck source=libexec/common.sh
. "$(dirname "$0")/common.sh"

usage() {
	cat >&2 <<'EOF'
usage: plans add <path-to-plan.md> [--as <slug>]
   eg: plans add .plans/2026-07-23-tts-timed-tokens.md
       plans add .plans/01-feat-auth.md --as 2026-07-23-feat-auth
EOF
}

plan_path=
slug_override=

while [ $# -gt 0 ]; do
	case $1 in
	--as)
		shift
		slug_override=${1:-}
		[ -n "$slug_override" ] || die "--as needs a slug."
		;;
	--as=*) slug_override=${1#--as=} ;;
	-h | --help)
		usage
		exit 0
		;;
	-*) die "Unknown option: $1" ;;
	*)
		[ -z "$plan_path" ] || die "One plan at a time (got $plan_path and $1)."
		plan_path=$1
		;;
	esac
	shift
done

if [ -z "$plan_path" ]; then
	usage
	exit 2
fi

[ -f "$plan_path" ] || die "No such plan file: $plan_path"

# The slug is the plan's permanent ID: it becomes the PLAN-<slug> reference in
# the commit message and the store path, so it is validated on the way in.
if [ -n "$slug_override" ]; then
	slug=${slug_override%.md}
	printf '%s' "$slug" | grep -Eq "$SLUG_RE" || {
		printf '❌ Not a plan ID: %s\n' "$slug" >&2
		printf '   Plan IDs are YYYY-MM-DD-slug — a date anyone can mint offline,\n' >&2
		printf '   plus a lowercase slug to separate two plans on the same day.\n' >&2
		exit 1
	}
else
	slug=$(basename "$plan_path" .md)
	printf '%s' "$slug" | grep -Eq "$SLUG_RE" || {
		printf '❌ Not a plan ID: %s\n' "$(basename "$plan_path")" >&2
		printf '   The store path is permanent once pushed, so mint it explicitly:\n\n' >&2
		printf '     plans add %s --as %s\n' "$plan_path" "$(suggest_slug "$plan_path")" >&2
		exit 1
	}
fi

stored_path="$STORE_DIR/$slug.md"

# A dedicated index, so .git/index is never disturbed. Left in place between runs:
# it is rebuilt from the ref every time, and is useful to inspect if a run goes wrong.
git_dir=$(git rev-parse --absolute-git-dir)
export GIT_INDEX_FILE="$git_dir/plans-index"

if parent=$(git rev-parse --verify --quiet "$STORE_REF"); then
	# Load the existing store, so the new tree carries every plan already in it.
	git read-tree "$STORE_REF"
	if git cat-file -e "$parent:$stored_path" 2>/dev/null; then
		action="Updated"
		commit_verb="update"
	else
		action="Stored"
		commit_verb="add"
	fi
else
	parent=
	git read-tree --empty
	action="Created store with"
	commit_verb="add"
fi

blob=$(git hash-object -w "$plan_path")
git update-index --add --cacheinfo "100644,$blob,$stored_path"
tree=$(git write-tree)

if [ -n "$parent" ] && [ "$tree" = "$(git rev-parse "$parent^{tree}")" ]; then
	echo "✅ Already stored and unchanged: $stored_path"
	exit 0
fi

if [ -n "$parent" ]; then
	commit=$(git commit-tree "$tree" -p "$parent" -m "plans: $commit_verb $slug")
else
	commit=$(git commit-tree "$tree" -m "plans: $commit_verb $slug")
fi

# Passing the old value makes git refuse the update if the ref moved since we read
# it; an empty old value asserts it did not exist at all. Either way, a plan added
# from another window in the meantime cannot be clobbered.
git update-ref -m "plans add: $commit_verb $slug" "$STORE_REF" "$commit" "${parent:-}"

echo "✅ $action $stored_path ($(git rev-parse --short "$STORE_REF"))"
echo "   Reference it from the commit message as: PLAN-$slug"
echo "   Publish it with: plans sync"

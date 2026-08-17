#!/usr/bin/env bash
#
# Configure this repo to fetch and reflog the plan store.
#
# Deliberately a command rather than a postinstall hook: it writes to the user's
# git config, and an install should not do that behind their back.
set -euo pipefail
# shellcheck source=libexec/common.sh
. "$(dirname "$0")/common.sh"

want_docs=false
want_autolink=false

while [ $# -gt 0 ]; do
	case $1 in
	--docs) want_docs=true ;;
	--autolink) want_autolink=true ;;
	-h | --help)
		echo "usage: plans init [--docs] [--autolink]" >&2
		exit 0
		;;
	*) die "Unknown option: $1" ;;
	esac
	shift
done

refspec="+$STORE_REF:$TRACK_REF"

if git config --get-all "remote.$REMOTE.fetch" | grep -qxF "$refspec"; then
	echo "✅ Fetch refspec already configured"
else
	git config --add "remote.$REMOTE.fetch" "$refspec"
	echo "✅ Added fetch refspec: $refspec"
fi

# Reflog the namespace, so a ref move you regret stays recoverable.
if [ "$(git config --get core.logAllRefUpdates || echo)" = always ]; then
	echo "✅ core.logAllRefUpdates already 'always'"
else
	git config core.logAllRefUpdates always
	echo "✅ Set core.logAllRefUpdates = always"
fi

# owner/repo from the remote URL, for the docs link and the autolink template.
repo_nwo() {
	git remote get-url "$REMOTE" 2>/dev/null |
		sed -E 's#^git@[^:]+:##; s#^ssh://git@[^/]+/##; s#^https?://[^/]+/##; s#\.git$##'
}

if [ "$want_docs" = true ]; then
	root=$(git rev-parse --show-toplevel)
	target="$root/docs/plans.md"
	if [ -e "$target" ]; then
		echo "⏭  docs/plans.md already exists — left untouched"
	else
		nwo=$(repo_nwo)
		mkdir -p "$root/docs"
		sed -e "s|{{REPO_NWO}}|${nwo:-your-org/your-repo}|g" \
			-e "s|{{MIRROR_BRANCH}}|$MIRROR_BRANCH|g" \
			"$(dirname "$0")/../docs/plans.md" >"$target"
		echo "✅ Wrote docs/plans.md"
	fi
fi

if [ "$want_autolink" = true ]; then
	nwo=$(repo_nwo)
	[ -n "$nwo" ] || die "Could not read owner/repo from the $REMOTE remote URL."
	command -v gh >/dev/null || die "--autolink needs the gh CLI."

	# is_alphanumeric captures the whole hyphenated slug, not just the leading date.
	if gh api "repos/$nwo/autolinks" -f key_prefix='PLAN-' \
		-f url_template="https://github.com/$nwo/blob/$MIRROR_BRANCH/$STORE_DIR/<num>.md" \
		-F is_alphanumeric=true >/dev/null 2>&1; then
		echo "✅ Created the PLAN- autolink on $nwo"
	else
		echo "⏭  Could not create the PLAN- autolink (it may already exist, or you may not be an admin)"
	fi
fi

echo
echo "   Fetch the store with: plans sync"

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

while [ $# -gt 0 ]; do
	case $1 in
	--docs) want_docs=true ;;
	-h | --help)
		echo "usage: plans init [--docs]" >&2
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

# The remote URL, read once and reduced to a host and an owner/repo. git accepts
# three punctuations of the same thing — git@host:acme/widgets.git,
# ssh://git@host:29418/acme/widgets.git and https://host/acme/widgets.git — so the
# substitutions below strip scheme, user and port in turn, whichever are present.
remote_bare=$(git remote get-url "$REMOTE" 2>/dev/null |
	sed -E 's#^[a-z+]+://##; s#^[^@/]*@##; s#\.git/?$##')
remote_host=${remote_bare%%[:/]*}
remote_owner_repo=$(printf '%s' "$remote_bare" | sed -E 's#^[^:/]+(:[0-9]+)?[:/]##')

if [ "$want_docs" = true ]; then
	root=$(git rev-parse --show-toplevel)
	target="$root/docs/plans.md"
	if [ -e "$target" ]; then
		echo "⏭  docs/plans.md already exists — left untouched"
	else
		mkdir -p "$root/docs"
		sed -e "s|{{OWNER_REPO}}|${remote_owner_repo:-your-org/your-repo}|g" \
			-e "s|{{MIRROR_BRANCH}}|$MIRROR_BRANCH|g" \
			"$(dirname "$0")/../docs/plans.md" >"$target"
		echo "✅ Wrote docs/plans.md"
	fi
fi

echo
echo "   Fetch the store with: plans sync"

# Printed rather than run: it changes repository settings, needs admin rights, and
# happens once in a repo's life — and a wrapper could only report that the API said
# no, not why. GitHub is the only host we know of with this feature. Its
# is_alphanumeric option makes the match span hyphens, so a token captures the
# whole plan ID rather than stopping at the end of the date.
if [ "$remote_host" = github.com ] && [ -n "$remote_owner_repo" ] && [ -n "$MIRROR_BRANCH" ]; then
	echo
	echo "   To make PLAN- tokens clickable on GitHub, run once (needs admin):"
	echo "     gh api repos/$remote_owner_repo/autolinks -f key_prefix='PLAN-' \\"
	echo "       -f url_template='https://github.com/$remote_owner_repo/blob/$MIRROR_BRANCH/$STORE_DIR/<num>.md' \\"
	echo "       -F is_alphanumeric=true"
fi

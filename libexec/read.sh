#!/usr/bin/env bash
#
# Read the store: list, show, grep.
#
# Thin wrappers over git, and that is the point — a project's contributor notes can
# name one command instead of spelling out ref paths, and where the store actually
# lives stays an implementation detail we can change.
set -euo pipefail
# shellcheck source=libexec/common.sh
. "$(dirname "$0")/common.sh"

command=${1:-}
shift || true

ref_exists "$STORE_REF" || die "No plans yet. Add one with: plans add <file>"

case $command in
list)
	git ls-tree -r --name-only "$STORE_REF" -- "$STORE_DIR" | sed "s|^$STORE_DIR/||; s|\.md$||"
	;;
show)
	slug=${1:-}
	[ -n "$slug" ] || {
		echo "usage: plans show <slug>" >&2
		exit 2
	}
	# Accept the commit-message form too, so a PLAN- token pastes straight in.
	slug=${slug#PLAN-}
	slug=${slug%.md}
	git cat-file blob "$STORE_REF:$STORE_DIR/$slug.md" 2>/dev/null ||
		die "No such plan: $slug (list them with: plans list)"
	;;
grep)
	[ $# -gt 0 ] || {
		echo "usage: plans grep <pattern>" >&2
		exit 2
	}
	# git grep exits 1 on no match; report that as a clean "nothing found".
	git grep -n "$@" "$STORE_REF" -- "$STORE_DIR" | sed "s|^$STORE_REF:$STORE_DIR/||" ||
		echo "(no matches)"
	;;
*)
	die "Unknown read command: $command"
	;;
esac

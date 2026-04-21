#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/lib/common.sh"

ensure_git_repo

hooks_path="scripts/repo-maintenance/hooks"

chmod +x "$REPO_ROOT/$hooks_path/pre-commit"
git -C "$REPO_ROOT" config core.hooksPath "$hooks_path"

log "Configured git hooks for this clone:"
log "  core.hooksPath = $hooks_path"
log "The pre-commit hook now runs scripts/repo-maintenance/validate-all.sh."

#!/usr/bin/env bash
# Read-only pre-publication check. Exit nonzero on obvious secret-bearing tracked files.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v git >/dev/null; then echo 'git missing'; exit 1; fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then echo 'Run git init before this check'; exit 1; fi
printf '=== Potentially sensitive tracked paths ===\n'
tracked="$(git ls-files --cached)"
if printf '%s\n' "$tracked" | grep -Ei '(^|/)(\.env($|\.)|.*\.sqlite3?$|.*\.db$|.*\.pem$|.*\.key$|.*keystore.*|.*signature.*\.json$|sentinel-evidence\.json|sentinel-chain-payments\.json|\.vercel/|node_modules/|__pycache__/|\.pyc$|broadcast/|cache/|out/|lib/)' ; then
  echo 'ERROR: investigate and untrack the paths above before publication.' >&2
  exit 2
fi
printf '%s\n' 'No obvious sensitive tracked path names. Review content manually before making repository public.'
git status --short

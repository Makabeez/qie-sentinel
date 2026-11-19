
#!/usr/bin/env bash
# QIE Sentinel — GitHub pre-publication security check
# Checks staged/tracked files before publishing.
# .env.example is allowed; actual .env files are blocked.

set -euo pipefail

cd "$(dirname "$0")/.."

echo "========================================"
echo " QIE Sentinel — Publication Security Check"
echo "========================================"
echo

# 1. Verify Git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: Not inside a Git repository."
    exit 1
fi

# 2. Collect staged/tracked filenames
mapfile -d '' -t tracked_files < <(git ls-files --cached -z)

if [ "${#tracked_files[@]}" -eq 0 ]; then
    echo "ERROR: No files are staged or tracked."
    exit 1
fi

echo "Checking ${#tracked_files[@]} tracked files..."
echo

# 3. Check sensitive filenames
sensitive_files=()

for file in "${tracked_files[@]}"; do
    name="${file##*/}"
    lower="${file,,}"
    basename_lower="${name,,}"

    # Safe configuration template, with public addresses only
    if [[ "$file" == ".env.example" ]]; then
        continue
    fi

    case "$basename_lower" in
        .env|.env.*|*.pem|*.key|*.p12|*.pfx|*.sqlite|*.sqlite3|*.db|*.keystore|*.secret)
            sensitive_files+=("$file")
            continue
            ;;
    esac

    case "$lower" in
        */.vercel/*|.vercel/*|*/node_modules/*|node_modules/*|*/__pycache__/*|__pycache__/*|*/broadcast/*|broadcast/*|*/cache/*|cache/*|*/out/*|out/*|*/lib/*|lib/*)
            sensitive_files+=("$file")
            continue
            ;;
    esac

    case "$basename_lower" in
        sentinel-evidence.json|sentinel-chain-payments.json|*.pyc)
            sensitive_files+=("$file")
            continue
            ;;
    esac

    # Wallet and signature files
    if [[ "$basename_lower" == *keystore* ]] ||
       [[ "$basename_lower" == *private_key* ]] ||
       [[ "$basename_lower" == *secret_key* ]] ||
       [[ "$basename_lower" == *signature*.json ]]; then
        sensitive_files+=("$file")
    fi
done

if [ "${#sensitive_files[@]}" -gt 0 ]; then
    echo "ERROR: Potentially sensitive files are tracked:"
    printf '  %s\n' "${sensitive_files[@]}"
    echo
    echo "Remove sensitive files from Git tracking:"
    echo "  git rm --cached -- <filename>"
    echo
    echo "The local file will not be deleted."
    exit 2
fi

echo "[PASS] No sensitive filenames detected."

# 4. Check for high-confidence credential patterns
# Only scan the Git index, not untracked local files.
# Show filenames only, never print potentially secret values.

secret_patterns=(
    '-----BEGIN .*PRIVATE KEY-----'
    'ghp_[A-Za-z0-9]{20,}'
    'gho_[A-Za-z0-9]{20,}'
    'ghu_[A-Za-z0-9]{20,}'
    'ghs_[A-Za-z0-9]{20,}'
    'github_pat_[A-Za-z0-9_]{20,}'
    'sk-proj-[A-Za-z0-9_-]{20,}'
    'sk-[A-Za-z0-9_-]{32,}'
)

credential_matches=()

for pattern in "${secret_patterns[@]}"; do
    while IFS= read -r -d '' matched; do
        credential_matches+=("$matched")
    done < <(
        git grep --cached -Ilz -E \
            -e "$pattern" -- . ':!scripts/check-publish.sh' \
            2>/dev/null || true
    )
done

if [ "${#credential_matches[@]}" -gt 0 ]; then
    echo "ERROR: Possible credentials detected in:"
    printf '%s\n' "${credential_matches[@]}" | sort -u
    echo
    echo "Review and remove secrets before publishing."
    exit 3
fi

echo "[PASS] No recognizable credentials detected."

# 5. Check staged whitespace errors
if ! git diff --cached --check; then
    echo "ERROR: Staged changes contain whitespace errors."
    exit 4
fi

echo "[PASS] No staged whitespace errors."

# 6. Summary
echo
echo "========================================"
echo " PUBLICATION CHECK PASSED"
echo "========================================"
echo
echo "Allowed: .env.example"
echo "Blocked: secrets, databases, keystores,"
echo "         private keys, generated local data"
echo
echo "Reminder: This is not a comprehensive secrets"
echo "scan. Review staged content before publishing."
echo
git status --short

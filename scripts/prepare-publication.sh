#!/usr/bin/env bash
# Idempotent local setup; never git push or deploy.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
root=Path('.')
source=root/'README-PUBLIC.md'
if not source.is_file():
    raise SystemExit('README-PUBLIC.md missing')
readme=root/'README.md'
backup=root/'README-before-v08.md'
if readme.exists() and not backup.exists():
    backup.write_bytes(readme.read_bytes())
readme.write_bytes(source.read_bytes())
ignore=root/'.gitignore'
existing=ignore.read_text() if ignore.exists() else ''
needed='''__pycache__/
*.pyc
*.db
*.db-*
*.sqlite
*.sqlite3
sentinel-evidence.json
sentinel-chain-payments.json
sentinel-showcase.html
README-before-v08.md
.env
.env.*
!.env.example
.vercel/
node_modules/
lib/
out/
cache/
broadcast/
'''
lines=set(existing.splitlines())
add=''.join(line+'\n' for line in needed.splitlines() if line not in lines)
ignore.write_text(existing + ('\n' if existing and not existing.endswith('\n') else '') + add)
PY
python3 scripts/check-public-site.py
printf '\nPrepared README and ignore rules; nothing committed or uploaded.\n'

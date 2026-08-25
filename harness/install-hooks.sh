#!/bin/bash
# Installs the harness git hooks. Run once per clone (hooks live in .git/,
# which git doesn't version — this script is the versioned source of truth).
set -euo pipefail
cd "$(dirname "$0")/.."

HOOK=".git/hooks/pre-commit"
cat > "$HOOK" <<'EOF'
#!/bin/bash
# Harness sensor gate: fast checks run on every commit (installed by
# harness/install-hooks.sh). Bypass in an emergency with: git commit --no-verify
exec "$(git rev-parse --show-toplevel)/harness/checks.sh"
EOF
chmod +x "$HOOK"
echo "Installed pre-commit hook -> harness/checks.sh"

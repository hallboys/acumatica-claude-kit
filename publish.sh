#!/usr/bin/env bash
# Patch-bump the plugin version, commit, and push. Run from anywhere:
#   ~/ClaudeCode/acumatica-claude-kit/publish.sh "what changed"
set -euo pipefail
cd "$(dirname "$0")"

msg="${1:-Update Acumatica knowledge}"
plugin_json="$(git ls-files | grep '/plugin\.json$' | head -1)"
[ -n "$plugin_json" ] || { echo "no plugin.json found" >&2; exit 1; }

# major.minor.PATCH -> bump PATCH
perl -i -pe 's/("version":\s*")(\d+\.\d+\.)(\d+)(")/$1.$2.($3+1).$4/e' "$plugin_json"
new_ver="$(perl -ne 'print $1 and last if /"version":\s*"([^"]+)"/' "$plugin_json")"

git add -A
git commit -q -m "$msg (v$new_ver)"
git push -q
echo "Pushed v$new_ver."
echo "To use the update locally: /plugin marketplace update && /reload-plugins"

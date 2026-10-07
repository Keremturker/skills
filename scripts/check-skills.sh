#!/usr/bin/env bash
# Checks the frontmatter rules of every <skill>/SKILL.md and that compass-kit/kit.json names
# existing skills. See docs/superpowers/specs/2026-10-08-model-routing-design.md.
# Usage: check-skills.sh [repo root]. Exit 0 ok, 1 violations (one "FAIL: <skill>: ..." each).
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
fail=0
bad() { echo "FAIL: $1: $2"; fail=1; }
fm() { # $1 = SKILL.md, $2 = key → top-level value (unquoted), empty when absent
  awk -v k="$2" 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit}
    NR>1 && index($0, k": ")==1 {v=substr($0, length(k)+3); gsub(/^["'\'']|["'\'']$/, "", v); print v; exit}' "$1"
}
INLINE_OK=" cmp-commit cmp-new-project cmp-matrix-test "
CODE_SKILLS=" cmp-code-rules cmp-feature cmp-design-to-code "
for f in "$ROOT"/*/SKILL.md; do
  [ -f "$f" ] || continue
  d="$(basename "$(dirname "$f")")"
  name="$(fm "$f" name)" model="$(fm "$f" model)" ctx="$(fm "$f" context)" bg="$(fm "$f" background)"
  [ "$name" = "$d" ] || bad "$d" "name '$name' does not match the folder"
  case "$model" in ''|opus|sonnet|haiku|fable|inherit) ;; *) bad "$d" "model '$model' is not opus|sonnet|haiku|fable|inherit" ;; esac
  [ "$ctx" != fork ] || [ "$bg" = false ] || bad "$d" "background must be false with context: fork"
  if [ -n "$model" ] && [ "$ctx" != fork ] && [[ "$INLINE_OK" != *" $d "* ]]; then
    bad "$d" "inline model switches the caller's turn; use context: fork"
  fi
  if [[ "$CODE_SKILLS" == *" $d "* ]] && { [ -n "$model" ] || [ -n "$ctx" ]; }; then
    bad "$d" "code skill must run on the session model (no model:, no context:)"
  fi
done
KIT="$ROOT/compass-kit/kit.json"
if [ -f "$KIT" ]; then
  while IFS= read -r s; do
    [ -f "$ROOT/$s/SKILL.md" ] || bad "$s" "listed in kit.json but $s/SKILL.md is missing"
  done < <(jq -r '.skills[] | if type == "string" then . else .name end' "$KIT")
fi
exit "$fail"

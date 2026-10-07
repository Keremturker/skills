#!/usr/bin/env bash
# Behavior test for check-skills.sh. Run: bash scripts/test_check_skills.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-skills.sh"
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok: $d"; else echo "FAIL: $d"; fail=1; fi; }
T="${TMPDIR:-/tmp}"; TMP="$(mktemp -d "${T%/}/check-skills.XXXXXX")" && [ -d "$TMP" ] || { echo "FAIL: mktemp"; exit 1; }
skill() { # $1 = dir, rest = frontmatter lines
  local d="$TMP/$1"; shift; mkdir -p "$d"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# x"; } > "$d/SKILL.md"
}
reset() { rm -rf "${TMP:?}"/*; mkdir -p "$TMP/compass-kit"; echo '{"skills":["a",{"name":"b","requires":"detekt"}]}' > "$TMP/compass-kit/kit.json"; skill a "name: a"; skill b "name: b"; }
runc() { OUT="$(bash "$CHECK" "$TMP" 2>&1)"; CODE=$?; }

reset; runc; check "clean tree passes" test "$CODE" -eq 0
check "real repo passes" bash "$CHECK"

reset; skill c "name: other"; runc
check "R1 name mismatch fails" bash -c '[ "$1" -eq 1 ] && grep -q "FAIL: c: name" <<<"$2"' _ "$CODE" "$OUT"
reset; skill c "name: c" "model: gpt" "context: fork" "background: false"; runc
check "R2 unknown model fails" bash -c '[ "$1" -eq 1 ] && grep -q "FAIL: c: model" <<<"$2"' _ "$CODE" "$OUT"
reset; skill c "name: c" "model: sonnet" "context: fork"; runc
check "R3 fork without background false fails" bash -c '[ "$1" -eq 1 ] && grep -q "FAIL: c: background" <<<"$2"' _ "$CODE" "$OUT"
reset; skill c "name: c" "model: sonnet"; runc
check "R4 inline model outside allowlist fails" bash -c '[ "$1" -eq 1 ] && grep -q "FAIL: c: inline model" <<<"$2"' _ "$CODE" "$OUT"
reset; skill cmp-commit "name: cmp-commit" "model: sonnet"; runc
check "R4 inline model in cmp-commit passes" test "$CODE" -eq 0
reset; skill cmp-feature "name: cmp-feature" "context: fork" "background: false"; runc
check "R5 code skill with context fails" bash -c '[ "$1" -eq 1 ] && grep -q "FAIL: cmp-feature: code skill" <<<"$2"' _ "$CODE" "$OUT"
reset; rm -rf "${TMP:?}/b"; runc
check "R6 kit skill without folder fails" bash -c '[ "$1" -eq 1 ] && grep -q "FAIL: b: listed in kit.json" <<<"$2"' _ "$CODE" "$OUT"
reset; skill c "name: c" "description: >-" "  model: opus in text" "context: fork" "background: false"; runc
check "indented text inside a folded value is not a key" test "$CODE" -eq 0

rm -rf "${TMP:?}"
exit "$fail"

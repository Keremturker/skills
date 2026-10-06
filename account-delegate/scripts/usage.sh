#!/usr/bin/env bash
# Token and cost use of both accounts since a day. Usage: usage.sh [--since YYYY-MM-DD]
# Second account: the delegated jobs in DELEGATE_CACHE_DIR (cost as the CLI reports it).
# Main account: the session transcripts in USAGE_MAIN_PROJECTS_DIR (default ~/.claude/projects;
# no cost there, tokens only). --since defaults to 7 days ago; days are compared in UTC.
set -uo pipefail

usage() { echo "usage: usage.sh [--since YYYY-MM-DD]" >&2; exit 2; }
SINCE="$(date -u -v-7d +%Y-%m-%d 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%d)"
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in --since) SINCE="$2" ;; *) usage ;; esac
  shift 2
done
[[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage
CACHE="${DELEGATE_CACHE_DIR:-$HOME/.cache/claude-delegate}"
PROJECTS="${USAGE_MAIN_PROJECTS_DIR:-$HOME/.claude/projects}"

table() { # TSV on stdin, first line is the header; right-aligns every column but the first
  awk -F'\t' '{ for (i = 1; i <= NF; i++) { c[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) } n = NR; if (NF > m) m = NF }
    END { for (r = 1; r <= n; r++) { line = sprintf("%-" w[1] "s", c[r, 1])
            for (i = 2; i <= m; i++) line = line sprintf("  %" w[i] "s", c[r, i]); print line } }'
}

echo "Second account (delegated jobs, $CACHE) since $SINCE"
{
  shopt -s nullglob
  # only job dirs: <cache>/<id>/ and <cache>/plans/<plan>/jobs/<n>/ (never files inside a worktree)
  for ev in "$CACHE"/*/events.jsonl "$CACHE"/plans/*/jobs/*/events.jsonl; do
    dir="$(dirname "$ev")"
    started="$(jq -r '.started_at // empty' "$dir/meta.json" 2>/dev/null)"
    [ -n "$started" ] && [[ "${started:0:10}" < "$SINCE" ]] && continue
    rel="${dir#"$CACHE"/}"
    case "$rel" in plans/*/jobs/*) group="${rel#plans/}"; group="${group%%/*}" ;; *) group="single jobs" ;; esac
    jq -R -c --arg g "$group" 'fromjson? | select(.type == "result")
      | {g: $g, c: (.total_cost_usd // 0), o: (.usage.output_tokens // 0),
         cr: (.usage.cache_read_input_tokens // 0), cw: (.usage.cache_creation_input_tokens // 0)}' "$ev" | tail -n 1
  done
} | jq -s -r '
  def row: [.[0].g, length, "$" + ((map(.c) | add) * 100 | round / 100 | tostring
              | if test("\\.") then (if test("\\.[0-9]$") then . + "0" else . end) else . + ".00" end),
            (map(.o) | add), (map(.cr) | add), (map(.cw) | add)];
  (["GROUP", "JOBS", "COST", "OUTPUT", "CACHE_READ", "CACHE_WRITE"] | @tsv),
  (group_by(.g)[] | row | @tsv),
  ((if length == 0 then [{g: "TOTAL", c: 0, o: 0, cr: 0, cw: 0}] | row | .[1] = 0 else map(.g = "TOTAL") | row end) | @tsv)' | table

echo
echo "Main account (session transcripts, $PROJECTS) since $SINCE"
{
  [ ! -d "$PROJECTS" ] || find "$PROJECTS" -name '*.jsonl' -type f -newermt "$SINCE" -print0 \
    | xargs -0 jq -R -c --arg since "$SINCE" --arg root "$PROJECTS/" 'fromjson?
        | select(.type == "assistant" and .message.usage and .message.id and ((.timestamp // "")[0:10] >= $since))
        | {p: (input_filename | ltrimstr($root) | split("/")[0]), id: .message.id,
           o: (.message.usage.output_tokens // 0), cr: (.message.usage.cache_read_input_tokens // 0),
           cw: (.message.usage.cache_creation_input_tokens // 0)}' 2>/dev/null
} | jq -s -r '
  def row: [.[0].p, length, (map(.o) | add), (map(.cr) | add), (map(.cw) | add)];
  unique_by(.id) as $m |
  (["PROJECT", "MESSAGES", "OUTPUT", "CACHE_READ", "CACHE_WRITE"] | @tsv),
  ($m | group_by(.p)[] | row | @tsv),
  ((if ($m | length) == 0 then ["TOTAL", 0, 0, 0, 0] else ($m | map(.p = "TOTAL") | row) end) | @tsv)' | table

# Renders one Claude Code stream-json line (read with jq -R) as one human-readable line.
# Non-JSON or partial lines are skipped.
def clip($n): tostring | gsub("[\r\n\t]+"; " ") | if length > $n then .[0:$n] + "…" else . end;
def tool_arg: (.file_path // .path // .pattern // .command // .url // .query // .description // "") | clip(100);
def result_text: if type == "array" then map(.text? // "") | join(" ") else (. // "") end;

(fromjson? // empty)
| if .type == "system" and .subtype == "init" then
    "● started · model: \(.model // "?") · cwd: \(.cwd // "?")"
  elif .type == "assistant" then
    (.message.content // [])[]
    | if .type == "text" then "· \(.text | clip(200))"
      elif .type == "tool_use" then "→ \(.name) \(.input | tool_arg)"
      else empty end
  elif .type == "user" then
    (.message.content // []) | if type == "array" then .[] else empty end
    | select(.type == "tool_result" and .is_error == true)
    | "✗ \(.content | result_text | clip(150))"
  elif .type == "result" then
    "■ finished · \(.subtype // "?") · turns: \(.num_turns // "?") · cost: $\(.total_cost_usd // 0)"
  else empty end

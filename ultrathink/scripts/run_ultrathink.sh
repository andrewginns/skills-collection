#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

DEFAULT_MODEL="gpt-5.2-pro"
DEFAULT_API_BASE="https://api.openai.com/v1"
DEFAULT_TIMEOUT_SEC=7200
DEFAULT_POLL_INTERVAL_SEC=15
DEFAULT_MAX_CONTEXT_CHARS=50000

PLAN_FIRST_INSTRUCTIONS="You are an ultrathink planning assistant. Plan first and surface big forks early. Before recommending action, enumerate the major approaches, their tradeoffs, risks, and required assumptions. Then recommend the best path and provide a concrete execution plan."

usage() {
  cat <<'EOF'
Usage:
  run_ultrathink.sh --query "<text>" [options]
  run_ultrathink.sh --query-file <path> [options]
  run_ultrathink.sh --query-stdin [options]
  run_ultrathink.sh --resume-response-id <resp_id> [options]

Options:
  --query <text>                    Primary user request.
  --query-file <path>               Primary user request read from file.
  --query-stdin                     Primary user request read from stdin.
  --context-text <text>             Additional context string (repeatable).
  --context-file <path>             Additional context file (repeatable).
  --max-context-chars <n>           Cap assembled input length (default: 50000).
  --resume-response-id <id>         Poll an existing response instead of submitting.
  --submit-only                     Submit and return response id without polling.
  --model <id>                      Model id (default: gpt-5.2-pro).
  --service-tier <tier>             auto|default|flex|priority (default: priority).
  --reasoning-effort <effort>       none|minimal|low|medium|high|xhigh (default: high).
  --verbosity <level>               low|medium|high (default: medium).
  --poll-interval-sec <n>           Poll interval in seconds (default: 15).
  --timeout-sec <n>                 Poll timeout in seconds (default: 3600).
  --api-base <url>                  API base URL (default: OPENAI_API_BASE or https://api.openai.com/v1).
  --metadata KEY=VALUE              Metadata pair (repeatable).
  --output-json <path>              Write final response JSON to file.
  --show-prompt                     Print assembled input text before submit.
  -h, --help                        Show this help message.

Environment:
  OPENAI_API_KEY                    Required.
  OPENAI_API_BASE                   Optional override for API base.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

trim() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

validate_int_ge_1() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || fail "$name must be an integer >= 1"
  (( value >= 1 )) || fail "$name must be >= 1"
}

pretty_json_to_stderr() {
  local body="$1"
  if jq -e . >/dev/null 2>&1 <<<"$body"; then
    jq . >&2 <<<"$body"
  else
    echo "$body" >&2
  fi
}

api_request() {
  local method="$1"
  local url="$2"
  local data="${3-}"

  local response_with_status
  if [[ -n "$data" ]]; then
    response_with_status="$(
      curl -sS -X "$method" "$url" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$data" \
        -w $'\n%{http_code}'
    )"
  else
    response_with_status="$(
      curl -sS -X "$method" "$url" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -w $'\n%{http_code}'
    )"
  fi

  local http_status="${response_with_status##*$'\n'}"
  local body="${response_with_status%$'\n'*}"

  if [[ ! "$http_status" =~ ^2[0-9][0-9]$ ]]; then
    echo "OpenAI API error (${http_status}) for ${method} ${url}" >&2
    pretty_json_to_stderr "$body"
    return 1
  fi

  printf '%s' "$body"
}

extract_output_text() {
  local response_json="$1"
  jq -r '
    .output_text //
    ([.output[]? | select(.type=="message") | .content[]? | select(.type=="output_text") | .text] | join("\n\n"))
  ' <<<"$response_json"
}

print_summary() {
  local response_json="$1"
  local rid status tier
  rid="$(jq -r '.id // "<unknown>"' <<<"$response_json")"
  status="$(jq -r '.status // "<unknown>"' <<<"$response_json")"
  tier="$(jq -r '.service_tier // "<unspecified>"' <<<"$response_json")"
  echo "response_id: $rid"
  echo "status: $status"
  echo "service_tier: $tier"
}

write_json_if_requested() {
  local response_json="$1"
  local output_path="$2"
  [[ -n "$output_path" ]] || return 0
  mkdir -p "$(dirname "$output_path")"
  jq . <<<"$response_json" >"$output_path"
}

OPENAI_API_KEY="${OPENAI_API_KEY:-}"
API_BASE="${OPENAI_API_BASE:-$DEFAULT_API_BASE}"
MODEL="$DEFAULT_MODEL"
SERVICE_TIER="priority"
REASONING_EFFORT="high"
VERBOSITY="medium"
POLL_INTERVAL_SEC="$DEFAULT_POLL_INTERVAL_SEC"
TIMEOUT_SEC="$DEFAULT_TIMEOUT_SEC"
MAX_CONTEXT_CHARS="$DEFAULT_MAX_CONTEXT_CHARS"
QUERY=""
QUERY_FILE=""
QUERY_STDIN=0
RESUME_RESPONSE_ID=""
SUBMIT_ONLY=0
SHOW_PROMPT=0
OUTPUT_JSON=""

declare -a CONTEXT_TEXTS=()
declare -a CONTEXT_FILES=()
declare -a METADATA_ITEMS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)
      [[ $# -ge 2 ]] || fail "Missing value for --query"
      QUERY="$2"
      shift 2
      ;;
    --query-file)
      [[ $# -ge 2 ]] || fail "Missing value for --query-file"
      QUERY_FILE="$2"
      shift 2
      ;;
    --query-stdin)
      QUERY_STDIN=1
      shift
      ;;
    --context-text)
      [[ $# -ge 2 ]] || fail "Missing value for --context-text"
      CONTEXT_TEXTS+=("$2")
      shift 2
      ;;
    --context-file)
      [[ $# -ge 2 ]] || fail "Missing value for --context-file"
      CONTEXT_FILES+=("$2")
      shift 2
      ;;
    --max-context-chars)
      [[ $# -ge 2 ]] || fail "Missing value for --max-context-chars"
      MAX_CONTEXT_CHARS="$2"
      shift 2
      ;;
    --resume-response-id)
      [[ $# -ge 2 ]] || fail "Missing value for --resume-response-id"
      RESUME_RESPONSE_ID="$2"
      shift 2
      ;;
    --submit-only)
      SUBMIT_ONLY=1
      shift
      ;;
    --model)
      [[ $# -ge 2 ]] || fail "Missing value for --model"
      MODEL="$2"
      shift 2
      ;;
    --service-tier)
      [[ $# -ge 2 ]] || fail "Missing value for --service-tier"
      SERVICE_TIER="$2"
      shift 2
      ;;
    --reasoning-effort)
      [[ $# -ge 2 ]] || fail "Missing value for --reasoning-effort"
      REASONING_EFFORT="$2"
      shift 2
      ;;
    --verbosity)
      [[ $# -ge 2 ]] || fail "Missing value for --verbosity"
      VERBOSITY="$2"
      shift 2
      ;;
    --poll-interval-sec)
      [[ $# -ge 2 ]] || fail "Missing value for --poll-interval-sec"
      POLL_INTERVAL_SEC="$2"
      shift 2
      ;;
    --timeout-sec)
      [[ $# -ge 2 ]] || fail "Missing value for --timeout-sec"
      TIMEOUT_SEC="$2"
      shift 2
      ;;
    --api-base)
      [[ $# -ge 2 ]] || fail "Missing value for --api-base"
      API_BASE="$2"
      shift 2
      ;;
    --metadata)
      [[ $# -ge 2 ]] || fail "Missing value for --metadata"
      METADATA_ITEMS+=("$2")
      shift 2
      ;;
    --output-json)
      [[ $# -ge 2 ]] || fail "Missing value for --output-json"
      OUTPUT_JSON="$2"
      shift 2
      ;;
    --show-prompt)
      SHOW_PROMPT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$OPENAI_API_KEY" ]] || fail "OPENAI_API_KEY is not set in the shell environment."
require_cmd curl
require_cmd jq

validate_int_ge_1 "--poll-interval-sec" "$POLL_INTERVAL_SEC"
validate_int_ge_1 "--timeout-sec" "$TIMEOUT_SEC"
validate_int_ge_1 "--max-context-chars" "$MAX_CONTEXT_CHARS"

if [[ "$SUBMIT_ONLY" -eq 1 && -n "$RESUME_RESPONSE_ID" ]]; then
  fail "--submit-only cannot be combined with --resume-response-id"
fi

query_source_count=0
[[ -n "$QUERY" ]] && query_source_count=$((query_source_count + 1))
[[ -n "$QUERY_FILE" ]] && query_source_count=$((query_source_count + 1))
[[ "$QUERY_STDIN" -eq 1 ]] && query_source_count=$((query_source_count + 1))

if [[ -z "$RESUME_RESPONSE_ID" && "$query_source_count" -eq 0 ]]; then
  fail "One of --query, --query-file, or --query-stdin is required unless --resume-response-id is provided."
fi

if [[ "$query_source_count" -gt 1 ]]; then
  fail "Use exactly one of --query, --query-file, or --query-stdin."
fi

case "$SERVICE_TIER" in
  auto|default|flex|priority) ;;
  *) fail "--service-tier must be one of: auto, default, flex, priority" ;;
esac

case "$REASONING_EFFORT" in
  none|minimal|low|medium|high|xhigh) ;;
  *) fail "--reasoning-effort must be one of: none, minimal, low, medium, high, xhigh" ;;
esac

case "$VERBOSITY" in
  low|medium|high) ;;
  *) fail "--verbosity must be one of: low, medium, high" ;;
esac

metadata_json='{}'
for kv in "${METADATA_ITEMS[@]+"${METADATA_ITEMS[@]}"}"; do
  [[ "$kv" == *=* ]] || fail "Invalid --metadata item (expected KEY=VALUE): $kv"
  key="${kv%%=*}"
  value="${kv#*=}"
  [[ -n "$key" ]] || fail "Metadata key cannot be empty: $kv"
  metadata_json="$(
    jq -cn \
      --argjson current "$metadata_json" \
      --arg key "$key" \
      --arg value "$value" \
      '$current + {($key): $value}'
  )"
done

response_json=""
if [[ -n "$RESUME_RESPONSE_ID" ]]; then
  response_json="$(api_request "GET" "${API_BASE%/}/responses/$RESUME_RESPONSE_ID")"
else
  if [[ -n "$QUERY_FILE" ]]; then
    [[ -f "$QUERY_FILE" ]] || fail "Query file not found: $QUERY_FILE"
    QUERY="$(cat "$QUERY_FILE")"
  fi

  if [[ "$QUERY_STDIN" -eq 1 ]]; then
    [[ -t 0 ]] && fail "--query-stdin requires piped stdin."
    QUERY="$(cat)"
  fi

  trimmed_query="$(printf '%s' "$QUERY" | trim)"
  [[ -n "$trimmed_query" ]] || fail "Primary query is empty."
  QUERY="$trimmed_query"

  declare -a context_blocks=()

  idx=0
  for value in "${CONTEXT_TEXTS[@]+"${CONTEXT_TEXTS[@]}"}"; do
    idx=$((idx + 1))
    trimmed_value="$(printf '%s' "$value" | trim)"
    [[ -n "$trimmed_value" ]] || continue
    context_blocks+=("[inline-$idx]
$trimmed_value")
  done

  for path in "${CONTEXT_FILES[@]+"${CONTEXT_FILES[@]}"}"; do
    [[ -f "$path" ]] || fail "Context file not found: $path"
    file_text="$(cat "$path")"
    trimmed_file_text="$(printf '%s' "$file_text" | trim)"
    [[ -n "$trimmed_file_text" ]] || continue
    context_blocks+=("[file:$path]
$trimmed_file_text")
  done

  input_text="Primary request:
$QUERY"

  if [[ "${#context_blocks[@]}" -gt 0 ]]; then
    joined_context=""
    for block in "${context_blocks[@]}"; do
      if [[ -n "$joined_context" ]]; then
        joined_context+=$'\n\n'
      fi
      joined_context+="$block"
    done
    input_text+=$'\n\nAdditional context:\n'
    input_text+="$joined_context"
  fi

  if (( ${#input_text} > MAX_CONTEXT_CHARS )); then
    input_text="${input_text:0:MAX_CONTEXT_CHARS}"
    input_text+=$'\n\n[Context truncated to '"$MAX_CONTEXT_CHARS"' characters by --max-context-chars.]'
  fi

  if [[ "$SHOW_PROMPT" -eq 1 ]]; then
    echo "===== assembled_input ====="
    echo "$input_text"
    echo "===== end_input ====="
  fi

  payload="$(
    jq -n \
      --arg model "$MODEL" \
      --arg instructions "$PLAN_FIRST_INSTRUCTIONS" \
      --arg input "$input_text" \
      --arg service_tier "$SERVICE_TIER" \
      --arg reasoning_effort "$REASONING_EFFORT" \
      --arg verbosity "$VERBOSITY" \
      --argjson metadata "$metadata_json" \
      '
      {
        model: $model,
        instructions: $instructions,
        input: $input,
        background: true,
        store: true,
        service_tier: $service_tier,
        reasoning: { effort: $reasoning_effort },
        text: { verbosity: $verbosity }
      }
      + (if ($metadata | length) > 0 then { metadata: $metadata } else {} end)
      '
  )"

  response_json="$(api_request "POST" "${API_BASE%/}/responses" "$payload")"
fi

print_summary "$response_json"
write_json_if_requested "$response_json" "$OUTPUT_JSON"

response_id="$(jq -r '.id // empty' <<<"$response_json")"
[[ -n "$response_id" ]] || fail "Response object missing id."
printf '%s\n' "$response_id" > ".ultrathink_response_id"

if [[ "$SUBMIT_ONLY" -eq 1 ]]; then
  exit 0
fi

status="$(jq -r '.status // empty' <<<"$response_json")"
start_time="$(date +%s)"
timed_out=0

while [[ "$status" == "queued" || "$status" == "in_progress" ]]; do
  now="$(date +%s)"
  elapsed=$((now - start_time))
  remaining=$((TIMEOUT_SEC - elapsed))
  if (( remaining <= 0 )); then
    timed_out=1
    break
  fi

  echo "[wait] status=$status elapsed=${elapsed}s remaining=${remaining}s"
  sleep_for="$POLL_INTERVAL_SEC"
  if (( sleep_for > remaining )); then
    sleep_for="$remaining"
  fi
  sleep "$sleep_for"

  response_json="$(api_request "GET" "${API_BASE%/}/responses/$response_id")"
  status="$(jq -r '.status // empty' <<<"$response_json")"
done

print_summary "$response_json"
write_json_if_requested "$response_json" "$OUTPUT_JSON"

if [[ "$timed_out" -eq 1 && ( "$status" == "queued" || "$status" == "in_progress" ) ]]; then
  echo
  echo "Timed out before reaching a terminal state."
  echo "Resume with:"
  echo "bash $SCRIPT_PATH --resume-response-id $response_id"
  exit 124
fi

output_text="$(extract_output_text "$response_json")"
if [[ -n "$output_text" ]]; then
  echo
  echo "===== ultrathink_output ====="
  echo "$output_text"
  echo "===== end_ultrathink_output ====="
else
  echo
  echo "No output_text found in final response payload."
fi

if [[ "$status" == "completed" ]]; then
  exit 0
fi

error_json="$(jq -c '.error // empty' <<<"$response_json")"
if [[ -n "$error_json" ]]; then
  echo
  echo "error:"
  jq '.error' <<<"$response_json"
fi

exit 1

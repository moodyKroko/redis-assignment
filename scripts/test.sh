#!/usr/bin/env bash

set -Eeuo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
BASE_URL="${BASE_URL%/}"

# ANSI color codes
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

for command in curl python3 mktemp; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        printf "${RED}ERROR: Required command not found: %s${NC}\n" \
            "${command}" >&2
        exit 1
    fi
done

TEMP_DIR="$(mktemp -d)"
RESPONSE_FILE="${TEMP_DIR}/response.json"

cleanup() {
    rm -rf -- "${TEMP_DIR}"
}

trap cleanup EXIT

fail() {
    printf "\n${RED}FAIL: %s${NC}\n" "$1" >&2

    if [[ -s "${RESPONSE_FILE}" ]]; then
        printf 'Response body:\n' >&2
        cat "${RESPONSE_FILE}" >&2
        printf '\n' >&2
    fi

    exit 1
}

pass() {
    printf "${GREEN}%s${NC}\n" "$1"
}

request() {
    local expected_status="$1"
    shift

    local actual_status

    : > "${RESPONSE_FILE}"

    if ! actual_status="$(
        curl \
            --silent \
            --show-error \
            --connect-timeout 3 \
            --max-time 10 \
            --output "${RESPONSE_FILE}" \
            --write-out '%{http_code}' \
            "$@"
    )"; then
        fail "Request failed. Check the application and URL: ${BASE_URL}"
    fi

    [[ "${actual_status}" == "${expected_status}" ]] \
        || fail "Expected HTTP ${expected_status}, received ${actual_status}."
}

assert_json() {
    local mode="$1"
    shift

    python3 - "${RESPONSE_FILE}" "${mode}" "$@" <<'PY'
import json
import sys

response_file, mode, *arguments = sys.argv[1:]

try:
    with open(response_file, encoding="utf-8") as response:
        data = json.load(response)
except (OSError, json.JSONDecodeError) as error:
    print(f"FAIL: Cannot read JSON response: {error}", file=sys.stderr)
    sys.exit(1)

if mode == "root":
    expected = {"message": "FastAPI is working"}
elif mode == "secret":
    expected = {"redis_password_configured": True}
elif mode == "store":
    key = arguments[0]
    expected = {"message": f"Stored key '{key}'"}
elif mode == "retrieve":
    key, value = arguments
    expected = {"key": key, "value": value}
elif mode == "missing":
    expected = {"detail": "Key not found"}
else:
    print(f"FAIL: Unknown assertion mode: {mode}", file=sys.stderr)
    sys.exit(1)

if data != expected:
    print(f"FAIL: Expected {expected!r}, received {data!r}", file=sys.stderr)
    sys.exit(1)
PY
}

printf 'Testing FastAPI at %s\n' "${BASE_URL}"

printf '\nWaiting for the HTTP endpoint'

http_ready=false

for ((attempt = 1; attempt <= 30; attempt++)); do
    if curl \
        --silent \
        --fail \
        --connect-timeout 1 \
        --max-time 2 \
        "${BASE_URL}/" \
        >/dev/null 2>&1; then
        http_ready=true
        break
    fi

    printf '.'
    sleep 1
done

printf '\n'

[[ "${http_ready}" == true ]] \
    || fail "HTTP endpoint did not become available."

request 200 "${BASE_URL}/"
assert_json root
pass 'PASS: FastAPI root endpoint'

request 200 "${BASE_URL}/secret-test"
assert_json secret
pass 'PASS: Redis password is configured in FastAPI'

RUN_ID="$(
    python3 -c 'import uuid; print(uuid.uuid4().hex)'
)"

KEY="stage5-${RUN_ID}"
VALUE="Hello from Stage 5: spaces & symbols + / ?"
MISSING_KEY="stage5-missing-${RUN_ID}"

request 200 \
    --request POST \
    --get \
    --data-urlencode "key=${KEY}" \
    --data-urlencode "value=${VALUE}" \
    "${BASE_URL}/cache"

assert_json store "${KEY}"
pass 'PASS: Value stored through FastAPI'

request 200 \
    --get \
    --data-urlencode "key=${KEY}" \
    "${BASE_URL}/cache"

assert_json retrieve "${KEY}" "${VALUE}"
pass 'PASS: Stored value retrieved correctly'

request 404 \
    --get \
    --data-urlencode "key=${MISSING_KEY}" \
    "${BASE_URL}/cache"

assert_json missing
pass 'PASS: Missing key returns HTTP 404'

printf "\n${GREEN}All 5 checks passed.${NC}\n"
printf 'Test key retained in Redis: %s\n' "${KEY}"

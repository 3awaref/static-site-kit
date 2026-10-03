#!/bin/sh
# Tests for gen-csp. Expected hashes were computed independently with Node.
# CI runs this inside the built base image (busybox awk):
#   docker run --rm -v "$PWD/test:/test:ro" <image> sh /test/run.sh
# Locally: GEN_CSP=image/gen-csp sh test/run.sh
set -u

gen="${GEN_CSP:-gen-csp}"
dir=$(cd "$(dirname "$0")" && pwd)/fixtures
out=$(mktemp)
fails=0

check() { # description, expected substring
    if grep -qF -- "$2" "$out"; then
        echo "ok   $1"
    else
        echo "FAIL $1: missing $2"
        sed 's/^/     /' "$out"
        fails=$((fails + 1))
    fi
}

expect_fail() { # description, webroot
    if "$gen" "$2" "$out" >/dev/null 2>&1; then
        echo "FAIL $1: gen-csp accepted it"
        fails=$((fails + 1))
    else
        echo "ok   $1"
    fi
}

"$gen" "$dir/multi" "$out" >/dev/null || { echo "FAIL multi: gen-csp exited non-zero"; exit 1; }
check "plain inline script hashed" "'sha256-3xqCEfNrbhQLAZy5uSLzJ9hNthXm1py/K8hqI37Cvoc='"
check "script with attributes hashed" "'sha256-FYljPxCFv3KLnyiqJ4ufzV0z8m0p4yNVgoaxeb7z1yA='"
check "nested page, UTF-8 bytes hashed" "'sha256-xZeaBSya9hIYeD5iUwf0M8TD+0SPqZnpdWqKrAlFgAw='"
check "script src adds 'self'" "script-src 'self' "
check "nginx include syntax" 'add_header Content-Security-Policy "default-src '"'none'"';'

"$gen" "$dir/empty" "$out" >/dev/null || { echo "FAIL empty: gen-csp exited non-zero"; exit 1; }
check "no scripts means script-src 'none'" "script-src 'none';"

CSP_EXTRA="connect-src 'self'; script-src https://cdn.example ; img-src https://img.example 'self'" \
    "$gen" "$dir/empty" "$out" >/dev/null || { echo "FAIL extra: gen-csp exited non-zero"; exit 1; }
check "extra replaces 'none'" "script-src https://cdn.example;"
check "extra appends without duplicates" "img-src 'self' data: https://img.example;"
check "extra adds new directive" "frame-ancestors 'none'; connect-src 'self'"

expect_fail "inline event handler rejected" "$dir/handler"
expect_fail "javascript: URL rejected" "$dir/jsurl"
CSP_EXTRA='img-src "x"' expect_fail "double quote in CSP_EXTRA rejected" "$dir/empty"

rm -f "$out"
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }

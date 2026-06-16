#!/bin/sh
# Tests for macos-im-switch: verifies input source querying and switching.
# Run: sh test-macos-im-switch.sh

HERE="$(dirname -- "$(readlink -f -- "$0")")/"
. "$HERE/utils.sh"

init_env

if [ ! -x "$TESTED_BIN" ]; then
    printf 'ERROR: %s not found or not executable\n' "$TESTED_BIN" >&2
    exit 1
fi

setup() { :; }

test_current() {
    desc "current returns non-empty source ID"
    output=$("$TESTED_BIN" current 2>&1)
    if [ -z "$output" ]; then
        fail "empty output"
        return 1
    fi
    if ! echo "$output" | grep -q '\.'; then
        fail "invalid format (no dot): $output"
        return 1
    fi
    pass "current = $output"
}

test_list() {
    desc "list shows at least one source"
    output=$("$TESTED_BIN" list 2>&1)
    if [ -z "$output" ]; then
        fail "empty output"
        return 1
    fi
    if ! echo "$output" | grep -q '\.'; then
        fail "invalid format"
        return 1
    fi
    pass "list has entries"
}

test_list_marks_current() {
    desc "list marks current source with *"
    current=$("$TESTED_BIN" current 2>&1)
    list_output=$("$TESTED_BIN" list 2>&1)
    if ! echo "$list_output" | grep -q "^\* $current$"; then
        fail "current source '$current' not marked with *"
        return 1
    fi
    pass "* marks $current"
}

test_set_silent() {
    desc "set command is silent on success"
    current=$("$TESTED_BIN" current 2>&1)
    output=$("$TESTED_BIN" set "$current" 2>&1)
    if [ -n "$output" ]; then
        fail "unexpected output: $output"
        return 1
    fi
    pass "no output on success"
}

test_set_invalid() {
    desc "set with invalid source fails gracefully"
    output=$("$TESTED_BIN" set "com.nonexistent.source" 2>&1)
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        fail "expected non-zero exit, got 0"
        return 1
    fi
    if ! echo "$output" | grep -qi "not found\|failed\|error"; then
        fail "no error message: $output"
        return 1
    fi
    pass "exit=$exit_code with error message"
}

test_roundtrip() {
    desc "round-trip switch preserves state"
    current=$("$TESTED_BIN" current 2>&1)

    # Try each alternative source until one works (some aren't selectable)
    if ! "$TESTED_BIN" list 2>&1 | while IFS= read -r line; do
        src=$(echo "$line" | sed 's/^[* ]*//')
        [ "$src" = "$current" ] && continue
        echo "$src" | grep -q '\.' || continue

        if "$TESTED_BIN" set "$src" >/dev/null 2>&1; then
            sleep 0.3
            new_current=$("$TESTED_BIN" current 2>&1)
            "$TESTED_BIN" set "$current" >/dev/null 2>&1
            if [ "$new_current" = "$src" ]; then
                pass "$current -> $src -> $current"
                exit 0
            fi
        fi
    done; then
        fail "no selectable alternative source found"
        return 1
    fi
}

test_no_args() {
    desc "no arguments defaults to current"
    output_no_args=$("$TESTED_BIN" 2>&1)
    output_current=$("$TESTED_BIN" current 2>&1)
    if [ "$output_no_args" != "$output_current" ]; then
        fail "outputs differ: '$output_no_args' vs '$output_current'"
        return 1
    fi
    pass "no-args == current"
}

test_usage() {
    desc "invalid command shows usage"
    output=$("$TESTED_BIN" invalid-command 2>&1)
    if ! echo "$output" | grep -qi "usage"; then
        fail "no usage message: $output"
        return 1
    fi
    pass "usage shown"
}

run_tests test_current \
    test_list \
    test_list_marks_current \
    test_set_silent \
    test_set_invalid \
    test_roundtrip \
    test_no_args \
    test_usage

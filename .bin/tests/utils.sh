#!/bin/sh
# General test utilities. Source first in test scripts.

# Print the path to the binary under test, derived from the calling
# test's filename: test-foo.sh -> <testdir>/../foo
get_tested_bin() {
    dir="$(cd "$(dirname "$0")" && pwd)/"
    target="${0##*/}"
    target="${target#test-}"
    target="${target%.sh}"
    printf '%s\n' "$dir/../$target"
}

# Print test header: [N] test_name
test_header() { printf '\n[%d] %s\n' "$1" "$2"; }

# Print an indented test description.
desc() { printf '  %s\n' "$1"; }

# Print an indented sub-step description (deeper than desc).
step() { printf '    %s\n' "$1"; }

# Print an indented pass/fail diagnostic.
pass() { printf '    %s\n' "$1"; }
fail() { printf '    FAIL: %s\n' "$1" >&2; }

# Print results summary. Exits 1 on any failure.
test_summary() {
    printf '\n==========================\n'
    printf 'Passed: %d/%d\n' "$1" "$2"
    if [ "$3" -gt 0 ]; then
        printf 'Failed: %d\n' "$3"
        exit 1
    fi
    echo "All tests passed!"
}

# Run all tests named in the space-separated list $@.
run_tests() {
    passed=0 failed=0 count=0
    for name in "$@"; do
        count=$((count + 1))
        test_header "$count" "$name"
        if (setup && eval "$name"); then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
            desc "FAILED"
        fi
    done
    test_summary "$passed" "$count" "$failed"
}

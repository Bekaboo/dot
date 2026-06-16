#!/bin/sh
# Tests for tmux-im: simulates pane switching scenarios.
# Run: sh test-tmux-im.sh

HERE="$(dirname -- "$(readlink -f -- "$0")")/"
. "$HERE/utils.sh"

init_env

export FCITX_STATE="$TEST_DIR/im-state"
export IM_STATUS_DIR="$TEST_DIR/im-status"

# Install mock executables in TEST_DIR (already on PATH).
install_mocks() {
    cat >"$TEST_DIR/uname" <<'MOCK'
#!/bin/sh
printf 'Linux\n'
MOCK
    chmod +x "$TEST_DIR/uname"

    cat >"$TEST_DIR/fcitx5-remote" <<'MOCK'
#!/bin/sh
case "$1" in
    -c) echo "0" > "$(dirname "$0")/im-state" ;;
    -o) echo "2" > "$(dirname "$0")/im-state" ;;
    *)  cat "$(dirname "$0")/im-state" ;;
esac
MOCK
    chmod +x "$TEST_DIR/fcitx5-remote"

    cat >"$TEST_DIR/tmux" <<'MOCK'
#!/bin/sh
STATUS_DIR="$(dirname "$0")/im-status"
case "$1" in
    set)
        pane=""; value=""; opt=""
        shift
        while [ $# -gt 0 ]; do
            case "$1" in
                -pt|-ptu) opt="$1"; shift; pane="$1"; shift ;;
                -t)      shift; pane="$1"; shift ;;
                *)       value="$1"; shift ;;
            esac
        done
        if [ "$opt" = "-ptu" ]; then
            rm -f "$STATUS_DIR/$pane"
        elif [ -n "$pane" ]; then
            echo "$value" > "$STATUS_DIR/$pane"
        fi
        ;;
    show)
        pane=""
        shift
        while [ $# -gt 0 ]; do
            case "$1" in
                -pt|-t) shift; pane="$1"; shift ;;
                *)      shift ;;
            esac
        done
        [ -f "$STATUS_DIR/$pane" ] && cat "$STATUS_DIR/$pane"
        ;;
    *)
        echo "tmux mock: unknown command: $*" >&2
        exit 1
        ;;
esac
MOCK
    chmod +x "$TEST_DIR/tmux"
}

install_mocks

setup() {
    rm -rf "$IM_STATUS_DIR"
    mkdir -p "$IM_STATUS_DIR"
    echo "2" >"$FCITX_STATE"
}

set_im() { echo "$1" >"$FCITX_STATE"; }
get_im() { cat "$FCITX_STATE"; }
get_im_status() { cat "$IM_STATUS_DIR/$1" 2>/dev/null || echo "<unset>"; }

assert_im() {
    actual="$(get_im)"
    if [ "$actual" != "$1" ]; then
        fail "expected IM state $1, got $actual"
        return 1
    fi
    pass "IM state = $actual"
}

assert_status() {
    actual="$(get_im_status "$1")"
    if [ "$actual" != "$2" ]; then
        fail "pane $1 @im_status expected $2, got $actual"
        return 1
    fi
    pass "@im_status($1) = $actual"
}

simulate_switch() {
    from="$1"
    to="$2"
    # focus-out from
    sh "$TESTED_BIN" save "$from"
    sh "$TESTED_BIN" force-off
    # focus-in to
    status="$(get_im_status "$to")"
    if [ "$status" = "CJK" ]; then
        sh "$TESTED_BIN" on "$to"
    else
        sh "$TESTED_BIN" force-off
    fi
}

simulate_kill_focused() {
    killed="$1"
    target="$2"
    # focus-out does NOT fire; IM may be leaked.
    status="$(get_im_status "$target")"
    if [ "$status" = "CJK" ]; then
        sh "$TESTED_BIN" on "$target"
    else
        sh "$TESTED_BIN" force-off
    fi
    sh "$TESTED_BIN" clear-status "$killed"
}

test_save_cjk() {
    desc "Save IM=CJK"
    set_im 2
    sh "$TESTED_BIN" save %0
    assert_im 2 || return 1
    assert_status %0 CJK || return 1
}

test_save_abc() {
    desc "Save IM=off"
    set_im 1
    sh "$TESTED_BIN" save %1
    assert_im 1 || return 1
    assert_status %1 ABC || return 1
}

test_force_off() {
    desc "Force-off turns IM off"
    set_im 2
    sh "$TESTED_BIN" force-off
    assert_im 0 || return 1
}

test_on_activates() {
    desc "On activates IM"
    set_im 0
    sh "$TESTED_BIN" on %0
    assert_im 2 || return 1
}

test_clear_status() {
    desc "Clear-status removes @im_status"
    sh "$TESTED_BIN" clear-status %0
    assert_status %0 "<unset>" || return 1
}

test_pane_switching() {
    desc "Switch A(CJK) -> B(ABC) -> A -> C(unset)"

    set_im 2
    sh "$TESTED_BIN" save %0
    assert_status %0 CJK || return 1
    set_im 1
    sh "$TESTED_BIN" save %1
    assert_status %1 ABC || return 1
    assert_status %2 "<unset>" || return 1

    step "A -> B"
    set_im 2
    simulate_switch %0 %1
    assert_im 0 || return 1
    assert_status %0 CJK || return 1

    step "B -> A"
    set_im 0
    simulate_switch %1 %0
    assert_im 2 || return 1
    assert_status %1 ABC || return 1

    step "A -> C"
    set_im 2
    simulate_switch %0 %2
    assert_im 0 || return 1
    assert_status %0 CJK || return 1
}

test_kill_focused_cjk_arrive_abc() {
    desc "Kill A(CJK focused), B(ABC) gets focus"

    set_im 2
    sh "$TESTED_BIN" save %0
    assert_status %0 CJK || return 1
    set_im 1
    sh "$TESTED_BIN" save %1
    assert_status %1 ABC || return 1

    simulate_kill_focused %0 %1
    assert_im 0 || return 1
    assert_status %0 "<unset>" || return 1
}

test_kill_focused_cjk_arrive_cjk() {
    desc "Kill A(CJK focused), B(CJK) gets focus"

    set_im 2
    sh "$TESTED_BIN" save %0
    sh "$TESTED_BIN" save %1
    assert_status %0 CJK || return 1
    assert_status %1 CJK || return 1

    simulate_kill_focused %0 %1
    assert_im 2 || return 1
    assert_status %0 "<unset>" || return 1
}

test_copymode() {
    desc "Copy-mode enter/exit with CJK"

    set_im 2
    sh "$TESTED_BIN" save %0
    assert_status %0 CJK || return 1
    sh "$TESTED_BIN" force-off
    assert_im 0 || return 1

    status="$(get_im_status %0)"
    if [ "$status" = "CJK" ]; then
        sh "$TESTED_BIN" on %0
    else
        sh "$TESTED_BIN" force-off
    fi
    assert_im 2 || return 1
}

run_tests test_save_cjk \
    test_save_abc \
    test_force_off \
    test_on_activates \
    test_clear_status \
    test_pane_switching \
    test_kill_focused_cjk_arrive_abc \
    test_kill_focused_cjk_arrive_cjk \
    test_copymode

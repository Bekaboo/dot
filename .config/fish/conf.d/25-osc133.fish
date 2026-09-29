# OSC133 support for fish < 4.0
# Source: https://codeberg.org/dnkl/foot/wiki#fish-2

if not status is-interactive; or test (string split . "$version")[1] -ge 4
    exit
end

function __osc133_cmd_start --on-event fish_preexec
    echo -en "\e]133;C\e\\"
end

function __osc133_cmd_end --on-event fish_postexec
    echo -en "\e]133;D\e\\"
end

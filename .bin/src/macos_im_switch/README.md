# macos-im-switch

Switch macOS input sources at the system level without focus loss.

Unlike `macism` which uses UI automation (accessibility features to click the
menu bar), this tool uses Carbon framework's `TISSelectInputSource` API to
switch input sources directly, avoiding the brief focus-stealing that triggers
tmux hooks and causes input method switching issues.

## Build

```sh
make
```

## Install

```sh
make install
```

This installs the binary to `~/.bin/macos-im-switch`.

## Usage

```sh
# Show current input source
macos-im-switch current

# List all available input sources (* marks current)
macos-im-switch list

# Switch to a specific input source (silent on success)
macos-im-switch set com.apple.inputmethod.SCIM.Shuangpin
```

## Testing

Only end-to-end testing is implemented for now.

```sh
cd ~/.bin/tests
sh test-macos-im-switch.sh
```

## Integration with tmux-im

This tool is designed to work with `tmux-im` for automatic input method
switching when changing tmux panes. The `tmux-im` script detects
`macos-im-switch` and uses it automatically on macOS.

---
name: dotfile-management
description: Load when user asks to commit, stage, diff, or do any git operation on dotfiles/config files under $HOME. Dotfiles are tracked in a bare git repo; use raw git invocation (the dot shell function is unavailable in fresh shells).
---

## Finding the git dir

The bare repo path is set by the `$DOT_DIR` environment variable. Look for it in:

1. `~/.profile`
2. `~/.bashrc`
3. Files sourced by the above (`source` / `.`)

If not defined, search for bare git repos under `$HOME`:

```bash
find "$HOME" -maxdepth 2 -name HEAD -path "*/.git/*" ! -path "*/.local/*" 2>/dev/null
```

## Git invocation

All standard git subcommands work. Prefix them with:

```bash
git --git-dir="$DOT_DIR" --work-tree="$HOME" <subcommand>
```

## Commit message style

Follow conventional commits format. Recent examples:
- `fix(firefox): square home page widgets`
- `fix(firefox): square urlbar dropdown panel`
- `refactor(firefox,thunderbird): move chrome CSS to stable config paths`
- `feat(thunderbird): square all UI elements`

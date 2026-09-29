---
name: create-skill
description: Load when the user asks to create or update an opencode agent skill. Provides the correct file structure, frontmatter format, naming rules, and description guidelines.
---

## File structure

Skills live at `~/.config/opencode/skills/<name>/SKILL.md` -- one directory per skill, file always named `SKILL.md` (uppercase).

## Frontmatter (YAML, required)

```yaml
---
name: <skill-name>          # required, must match directory name
description: <description>  # required, 1-1024 chars
license: <license>          # optional
compatibility: opencode     # optional
metadata:                   # optional, string-to-string map
  key: value
---
```

## Name rules

- 1-64 characters
- Lowercase alphanumeric with single hyphen separators only: `^[a-z0-9]+(-[a-z0-9]+)*$`
- Must not start or end with `-`, no consecutive `--`
- Must match the directory name

## Description guidelines

Focus on WHEN the agent should load the skill, not HOW it works. Start with a trigger condition:

Good: `Load when user asks to commit, stage, diff, or do any git operation on dotfiles.`
Bad: `Use bare git repo to stage and commit dotfile changes.`

## Content guidelines

Keep it concise. Skip enumerating standard commands if the skill is just a wrapper around an existing tool -- just state the invocation pattern and any project-specific conventions.

## Reference

Full docs: https://opencode.ai/docs/skills

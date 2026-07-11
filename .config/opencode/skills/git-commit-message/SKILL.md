---
name: git-commit-message
description: >-
  Load when user asks to create, amend, or use a Git commit message,
  especially when the message has a body, multiple paragraphs, rationale,
  validation notes, or other prose that would be awkward or unsafe to pass
  through repeated `git commit -m` arguments.
---

# Git Commit Message

## Workflow

1. Inspect the staged diff and write a conventional-commit subject that
   accurately describes it.
2. For a subject-only commit, `git commit -m "<subject>"` is acceptable.
3. For any message with a body, create `COMMIT_MSG` in the repository root by
   editing the file directly. Do not construct it with shell redirection,
   heredocs, escaped newlines, or multiple `-m` arguments.
4. Refuse to overwrite a pre-existing `COMMIT_MSG`; treat it as user-owned
   unless the current task created it.
5. Format the file as:

   ```text
   <conventional-commit subject>

   <body paragraph wrapped to at most 80 columns>

   <additional paragraph wrapped to at most 80 columns>
   ```

6. Keep the subject concise, preferably at most 72 characters. Separate the
   subject and every body paragraph with one blank line. Hard-wrap every prose
   line in body paragraphs to at most 80 columns. Preserve intentional
   unbreakable tokens such as URLs only when wrapping them is impractical.
7. Commit with `git commit -F COMMIT_MSG`. Amend with
   `git commit --amend -F COMMIT_MSG`.
8. After a successful commit, delete `COMMIT_MSG` only if this workflow created
   it. Preserve it when the commit fails so the message can be inspected or
   reused.

## Message Content

- Explain the behavior and design decision, not a chronological implementation
  log.
- Keep paragraphs focused on one idea.
- Include validation details only when they materially help future readers.
- Do not include generated boilerplate, praise, or claims unsupported by
  validation.

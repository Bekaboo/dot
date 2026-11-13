---
name: git-commit-message
description: >-
  Load when creating, amending, or using a Git commit message, including
  messages with a body or characters that make `git commit -m` unsafe.
---

# Git Commit Message

## Principle

Default to a single conventional-commit subject. A body is the exception, not
the norm. Follow the history of the touched paths for type, scope, and
wording; the examples below are defaults.

Aim for messages like:

```text
feat(parser): support quoted table names
fix(cli): do not crash on empty config
```

## Workflow

1. Inspect the staged diff and the history of each touched path with
   `git log --oneline --follow -- <path>`. Follow the established commit type,
   scope vocabulary, and wording. The file extension does not determine the
   type; the effect of the change and the file's history do.
2. Write the shortest conventional-commit subject that accurately describes
   the change. Add a body only when it clears the bar below.
3. Subject-only: `git commit -m "<subject>"`.
4. With a body: create `COMMIT_MSG` in the repository root by editing the file
   directly. Do not construct it with shell redirection, heredocs, escaped
   newlines, or multiple `-m` arguments.
5. Refuse to overwrite a pre-existing `COMMIT_MSG`; treat it as user-owned
   unless the current task created it.
6. Format the file as:

   ```text
   <conventional-commit subject>

   <body paragraph wrapped to at most 80 columns>
   ```
7. Separate the subject and body with one blank line. Hard-wrap every prose
   line at 80 columns. Preserve intentional unbreakable tokens such as URLs
   only when wrapping them is impractical.
8. Commit with `git commit -F COMMIT_MSG`. Amend with
   `git commit --amend -F COMMIT_MSG`.
9. After a successful commit, delete `COMMIT_MSG` only if this workflow created
   it. Preserve it when the commit fails so the message can be inspected or
   reused.

## When a body helps

Add a body only when the subject cannot carry the one thing a future reader
still needs:

- The non-obvious reason for the change, such as a workaround or a trade-off
- A user-visible side effect that the subject does not imply
- A migration or breaking-change note

Keep it to one short paragraph, at most two. Hold the whole message to about
five body lines; if it needs more, it is usually restating the diff, so cut it.

## Never include

- A file-by-file or function-by-function changelog
- A restatement of the subject
- A chronological implementation log
- Boilerplate, praise, or claims unsupported by validation

## Subject rules

- Conventional commit type and optional scope, imperative mood, lowercase
  after the scope, no trailing period, at most 72 characters.
- Name the identifier the change is about -- a constant, parameter, flag,
  type, command, etc. for searchability.
- One subject line only; never wrap it.

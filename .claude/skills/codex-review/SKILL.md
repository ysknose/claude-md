---
name: codex-review
description: This skill should be used when the user asks to
  "review code with Codex", "Codexでレビュー", "codex review",
  "Codexにレビューしてもらう", mentions using OpenAI Codex CLI for
  code review, or requests a Codex-based code review. TRIGGER when
  the user explicitly mentions Codex for review. DO NOT TRIGGER for
  general code review requests without mentioning Codex.
version: 1.0.0
---

# Codex CLI Code Review

Run a code review using the OpenAI Codex CLI (`codex review`)
subcommand.

## When This Skill Applies

- The user explicitly asks for a Codex-based code review
- The user types `/codex-review` or mentions "codex review"

## Procedure

### 1. Determine the review target

Parse the user's request to determine what to review:

| User Input | Command |
|---|---|
| No specific target | `codex review --uncommitted` (staged + unstaged + untracked) |
| Branch name (e.g., "main") | `codex review --base <branch>` |
| Commit SHA (7+ hex chars) | `codex review --commit <sha>` |
| Custom instructions | `codex review "<instructions>"` |

### 2. Execute the review command

Run the appropriate `codex review` command based on the
determined target.

```bash
# Default: review uncommitted changes
codex review --uncommitted

# Review against a branch
codex review --base <branch>

# Review a specific commit
codex review --commit <sha>

# Review with custom instructions
codex review "<custom instructions>"
```

### 3. Present the output

Display the Codex review output to the user as-is. Do not
summarize or filter.

## Tool Requirements

This skill requires the following Bash commands:
- `codex review` — Codex CLI review subcommand

## Examples

- "Codexでレビューして" → `codex review --uncommitted`
- "Codexで main との差分をレビュー" → `codex review --base main`
- "Codex review commit abc1234" → `codex review --commit abc1234`
- "Codexでセキュリティ重点のレビュー" → `codex review "focus on security issues"`

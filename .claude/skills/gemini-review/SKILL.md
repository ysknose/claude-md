---
name: gemini-review
description: This skill should be used when the user asks to
  "review code with Gemini", "Geminiでレビュー", "gemini review",
  "Geminiにレビューしてもらう", mentions using Google Gemini CLI
  for code review, or requests an external AI code review. TRIGGER
  when the user explicitly mentions Gemini for review. DO NOT
  TRIGGER for general code review requests without mentioning
  Gemini.
version: 1.0.0
---

# Gemini CLI Code Review

Run a code review by piping git diff output to the Gemini CLI
(`gemini -p`) in headless mode.

## When This Skill Applies

- The user explicitly asks for a Gemini-based code review
- The user types `/gemini-review` or mentions "gemini review"

## Procedure

### 1. Determine the diff target

Parse the user's request to determine what to review:

| User Input | Diff Command |
|---|---|
| No specific target | `git diff main...HEAD` (default: diff against main) |
| Branch name (e.g., "develop") | `git diff <branch>...HEAD` |
| Commit SHA (7+ hex chars) | `git show <sha>` |
| Custom instructions (e.g., "focus on security") | `git diff main...HEAD` + append instructions to prompt |

To verify branch/SHA, use `git rev-parse --verify <ref>` before
running the diff.

If the diff is empty, inform the user that there are no changes
to review and stop.

### 2. Build and execute the review command

Pipe the diff to `gemini -p` with the review prompt below. If the
user provided custom instructions, insert them into
`<additional_instructions>`.

```bash
<diff_command> | gemini -p "You are an expert code reviewer.
Review the following code diff thoroughly.

## Review Criteria
- **Bugs & Logic Errors**: Potential bugs, off-by-one errors,
null/undefined issues, race conditions
- **Security**: Injection vulnerabilities, hardcoded secrets,
insecure patterns (OWASP Top 10)
- **Performance**: Unnecessary re-renders, N+1 queries, memory
leaks, inefficient algorithms
- **Code Quality**: Readability, naming, DRY principle, proper
error handling
- **Best Practices**: Framework-specific patterns, proper typing,
consistent conventions

## Output Format
Categorize findings by severity:
- 🔴 **Critical**: Must fix before merge (bugs, security issues)
- 🟡 **Warning**: Should fix (performance, maintainability concerns)
- 🟢 **Info**: Nice to have (style, minor improvements)

For each finding, provide:
1. File and line reference
2. Description of the issue
3. Suggested fix with code example

End with a brief overall assessment and a summary table of
findings count by severity.

<additional_instructions>"
```

### 3. Present the output

Display the Gemini review output to the user as-is. Do not
summarize or filter.

## Tool Requirements

This skill requires the following Bash commands:
- `gemini -p "..."` — Gemini CLI in headless mode
- `git diff` / `git show` — to generate code diffs
- `git rev-parse` — to verify refs

## Examples

- "Geminiでレビューして" → `git diff main...HEAD | gemini -p "..."`
- "Geminiで develop ブランチとの差分をレビュー" → `git diff develop...HEAD | gemini -p "..."`
- "Gemini review commit abc1234" → `git show abc1234 | gemini -p "..."`
- "Geminiでセキュリティ重点のレビュー" → `git diff main...HEAD | gemini -p "... セキュリティに特に注意してレビュー ..."`

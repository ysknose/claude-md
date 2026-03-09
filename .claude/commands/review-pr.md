# PR レビューウィザード

PR をレビューし、問題があれば修正依頼（request-changes）+ 紐づく Issue に `pr-fix-needed` ラベルを付与する。

## Step 1: 対象 PR を取得

```bash
# レビュー待ちの PR（自分がレビュー依頼されたもの）
gh pr list --review-requested "@me" --state open --json number,title,url,author,headRefName

# 全 open PR
gh pr list --state open --json number,title,url,author,headRefName,reviewDecision
```

両方の結果を表示する。`reviewDecision` が `APPROVED` の PR はスキップ候補として表示。

また、**`reviewing` ラベルが付いている PR は別セッションがレビュー中のためスキップする**（重複作業防止）。

```bash
# reviewing ラベル付き PR を確認（スキップ対象）
gh pr list --state open --label "reviewing" --json number,title
```

## Step 2: 対象 PR を確認

**全ての open PR を対象にレビューする（ただし `reviewing` ラベル付きはスキップ）。AskUserQuestion は使わず、そのまま進む。**

## Step 2.5: ラベルを準備 & `reviewing` ラベルを付与

レビューを開始する前に、必要なラベルを作成し、対象 PR に `reviewing` ラベルを付与する。

```bash
# ラベルが存在しない場合は作成
gh label create "reviewing" --color "0075CA" --description "現在レビュー中（別セッションはスキップ）" 2>/dev/null || true
gh label create "review-complete" --color "0E8A16" --description "レビュー完了" 2>/dev/null || true
gh label create "pr-fix-needed" --color "D93F0B" --description "PR のレビュー指摘対応が必要" 2>/dev/null || true

# 対象 PR に reviewing ラベルを付与
gh pr edit <number> --add-label "reviewing"
```

## Step 3: Worktree を準備

PR ブランチをチェックアウトして動作確認できる環境を作る。

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
WORKTREE_BASE="/workspace/${REPO_NAME}-worktrees"

git fetch origin <headRefName>
git worktree add $WORKTREE_BASE/pr-<number> origin/<headRefName>
```

## Step 4: PR ごとにレビュー実行

各 PR について以下を実施する。

### 1. PR 情報を取得

```bash
gh pr view <number> --json title,body,files,additions,deletions,commits,headRefName
```

### 2. 差分を取得

```bash
gh pr diff <number>
```

### 3. Gemini CLI レビュー

差分を Gemini CLI にパイプしてレビューを取得する。

```bash
gh pr diff <number> | gemini -m gemini-3.1-pro-preview -p "You are an expert code reviewer.
Review the following code diff thoroughly.

## Review Criteria
- **Bugs & Logic Errors**: Potential bugs, off-by-one errors, null/undefined issues, race conditions
- **Security**: Injection vulnerabilities, hardcoded secrets, insecure patterns (OWASP Top 10)
- **Performance**: Unnecessary re-renders, N+1 queries, memory leaks, inefficient algorithms
- **Code Quality**: Readability, naming, DRY principle, proper error handling
- **Best Practices**: Framework-specific patterns, proper typing, consistent conventions

## Output Format
Categorize findings by severity:
- 🔴 Critical: Must fix before merge (bugs, security issues)
- 🟡 Warning: Should fix (performance, maintainability concerns)
- 🟢 Info: Nice to have (style, minor improvements)

For each finding, provide:
1. File and line reference
2. Description of the issue
3. Suggested fix with code example

End with a brief overall assessment and a summary table of findings count by severity."
```

`gemini` コマンドが存在しない場合はスキップし、`GEMINI_STATUS="スキップ（コマンド未インストール）"` として記録する。
実行した場合は以下を記録する:
```bash
GEMINI_STATUS="実施"
GEMINI_MODEL="gemini-3.1-pro-preview"
```

### 4. Codex CLI レビュー

Worktree 内で `codex exec review` を使って PR ブランチの差分をレビューする。
（`gh pr diff | codex exec "prompt"` 形式ではプロンプトが引数になりstdinが無視されるため不可）

```bash
cd $WORKTREE_BASE/pr-<number>
codex exec review --base main "You are an expert code reviewer.
Review the changes in this PR thoroughly.

## Review Criteria
- **Bugs & Logic Errors**: Potential bugs, off-by-one errors, null/undefined issues, race conditions
- **Security**: Injection vulnerabilities, hardcoded secrets, insecure patterns (OWASP Top 10)
- **Performance**: Unnecessary re-renders, N+1 queries, memory leaks, inefficient algorithms
- **Code Quality**: Readability, naming, DRY principle, proper error handling
- **Best Practices**: Framework-specific patterns, proper typing, consistent conventions

## Output Format
Categorize findings by severity:
- Critical: Must fix before merge (bugs, security issues)
- Warning: Should fix (performance, maintainability concerns)
- Info: Nice to have (style, minor improvements)

For each finding, provide:
1. File and line reference
2. Description of the issue
3. Suggested fix with code example

End with a brief overall assessment and a summary table of findings count by severity."
cd $REPO_ROOT
```

`codex` コマンドが存在しない場合はスキップし、`CODEX_STATUS="スキップ（コマンド未インストール）"` として記録する。
実行した場合は以下を記録する:
```bash
CODEX_STATUS="実施"
CODEX_MODEL=$(codex --version 2>/dev/null | grep -oE 'o[0-9]+[a-z-]*|gpt-[a-z0-9._-]+' | head -1 || echo "codex-cli")
```

### 5. 紐づく Issue を確認

PR body から `Closes #N` / `Fixes #N` / `Resolves #N` を解析して Issue 番号を取得する。

```bash
gh pr view <number> --json body --jq '.body'
```

Issue が見つかった場合はその内容も取得:
```bash
gh issue view <issue_number> --json title,body,labels
```

### 6. 静的コードレビュー（統合判定）

Gemini・Codex・Claude の 3 者のレビュー結果を統合して最終判定を行う。
以下の観点で各レビュアーの指摘を整理し、重複や補完関係を考慮する:

- **機能要件**: Issue の要件を満たしているか
- **コード品質**: 命名、構造、重複、可読性
- **セキュリティ**: インジェクション、XSS、認証漏れ等
- **パフォーマンス**: 明らかなボトルネックがないか
- **テスト**: テストが必要な変更にテストがあるか
- **破壊的変更**: 既存機能への影響がないか

複数のレビュアーが同じ問題を指摘している場合は重要度が高い。いずれか 1 者のみの指摘は文脈を考慮して判断する。

各指摘には必ずどの AI が発見したかを記録する。同一の問題を複数の AI が指摘した場合は 1 件にまとめ、全ての指摘元を列挙する。
フォーマット: `[Claude]` / `[Gemini]` / `[Codex]` / `[Claude, Gemini]` など

### 7. 動作チェック

Worktree 上で dev サーバーを起動し、chrome-devtools MCP でブラウザエラーを確認する。

```bash
cd $WORKTREE_BASE/pr-<number>
pnpm install
pnpm dev -- -p 3001 &
DEV_PID=$!
```

サーバー起動後、chrome-devtools MCP を使って動作確認:

1. **ページアクセス**: 変更に関連する画面を開く
2. **コンソールエラー**: `list_console_messages`（types: error, warn）でエラーがないか確認
3. **ネットワークエラー**: 4xx/5xx レスポンスがないか確認
4. **表示崩れ**: スクリーンショットを取得して目視確認

確認後、dev サーバーを停止:
```bash
kill $DEV_PID
```

## Step 5: レビュー結果に基づいてアクション

### 問題なしの場合

```bash
gh pr review <number> --approve --body "LGTM 👍

---
**このレビューは以下の AI によって自動実施されました**

| レビュアー | モデル | ステータス |
|-----------|-------|----------|
| Claude | claude-sonnet-4-6 | 実施 |
| Gemini | ${GEMINI_MODEL:-スキップ} | ${GEMINI_STATUS:-スキップ} |
| Codex | ${CODEX_MODEL:-スキップ} | ${CODEX_STATUS:-スキップ} |"

# reviewing を外して review-complete を付与
gh pr edit <number> --remove-label "reviewing" --add-label "review-complete"
```

### 修正が必要な場合

```bash
# レビューコメントを投稿（request-changes）
gh pr review <number> --request-changes --body "## レビュー指摘

### 🔴 Critical（マージ前に必須）
- [ ] \`[Claude, Gemini]\` \`src/foo.ts:42\` 指摘内容と修正提案

### 🟡 Warning（対応推奨）
- [ ] \`[Codex]\` \`src/bar.ts:10\` 指摘内容と修正提案

### 🟢 Info（任意）
- [ ] \`[Claude]\` 指摘内容と修正提案

> **凡例**: \`[Claude]\` \`[Gemini]\` \`[Codex]\` — 指摘した AI。複数表記は複数の AI が同一問題を検出したことを示す。

---
**このレビューは以下の AI によって自動実施されました**

| レビュアー | モデル | ステータス |
|-----------|-------|----------|
| Claude | claude-sonnet-4-6 | 実施 |
| Gemini | ${GEMINI_MODEL:-スキップ} | ${GEMINI_STATUS:-スキップ} |
| Codex | ${CODEX_MODEL:-スキップ} | ${CODEX_STATUS:-スキップ} |"

# 紐づく Issue に pr-fix-needed ラベルを付与
gh issue edit <issue_number> --add-label "pr-fix-needed"

# reviewing を外して review-complete を付与
gh pr edit <number> --remove-label "reviewing" --add-label "review-complete"
```

※ 紐づく Issue が見つからない場合は、新たに Issue を作成して `pr-fix-needed` ラベルを付与する:

```bash
# 紐づく Issue がない場合: Issue を新規作成して pr-fix-needed を付与
NEW_ISSUE_URL=$(gh issue create \
  --title "fix: PR #<number> のレビュー指摘対応" \
  --body "## 概要
PR #<number> に対するレビュー指摘の対応が必要です。

## 関連 PR
<PR の URL>

## 指摘内容
<指摘事項の要約>

---
*この Issue は AI によって自動作成されました*" \
  --label "pr-fix-needed")
echo "Created issue: $NEW_ISSUE_URL"
```

# reviewing を外して review-complete を付与
gh pr edit <number> --remove-label "reviewing" --add-label "review-complete"
```

## Step 6: Worktree クリーンアップ & 結果報告

```bash
git worktree remove $WORKTREE_BASE/pr-<number> --force
```

| PR | タイトル | Gemini | Codex | Claude | 動作チェック | 結果 | Issue |
|----|---------|--------|-------|--------|------------|------|-------|
| #N | ...     | OK     | OK    | OK     | OK         | approve | - |
| #N | ...     | 指摘あり | スキップ | 指摘あり | エラーあり | request-changes | #M に pr-fix-needed 付与 |

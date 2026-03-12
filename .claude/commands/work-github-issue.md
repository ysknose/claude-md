  # Issue 並列対応ウィザード

  メインエージェントとして GitHub Issue を管理し、git worktree +
   サブエージェントで並列対応する。
  `pr-fix-needed` ラベル付き Issue は、紐づく PR
  のレビュー指摘を修正する。

  ## Step 1: Issue リストを取得

  `claude-in-progress` ラベルおよび `claude-done`
  ラベルが付いている Issue は除外する。ただし `pr-fix-needed`
  が付いた Issue は `claude-done` であっても再処理する。

  ```bash
  # 通常の Issue（pr-fix-needed, claude-in-progress, claude-done
   を除外）
  gh issue list --state open --search "-label:claude-in-progress
   -label:claude-done -label:pr-fix-needed" --json
  number,title,labels,body --limit 50

  # PR 修正が必要な Issue（claude-in-progress
  のみ除外。claude-done でも pr-fix-needed があれば再処理する）
  gh issue list --state open --label "pr-fix-needed" --search
  "-label:claude-in-progress" --json number,title,labels,body
  --limit 50
  ```

  両方の結果を「📋 新規実装」「🔧 PR
  修正」でグルーピングしてユーザーに表示する。

  ## Step 2: 対象 Issue を決定

  **全件自動対応**: 見つかった Issue
  はすべて対象とする。質問せずにそのまま Step 3 へ進む。
  Issue が0件の場合のみ「対応可能な Issue
  はありません」と報告して終了する。

  ## Step 3: 処理中ラベルを付与 & Worktree を準備

  対象 Issue に `claude-in-progress`
  ラベルを付けて処理中であることを宣言し、git worktree
  を作成する。

  ### パス変数の決定

  以下の変数を動的に決定する（ハードコードしない）:

  ```bash
  REPO_ROOT=$(git rev-parse --show-toplevel)       # 例:
  /workspace/poc-sales
  REPO_NAME=$(basename "$REPO_ROOT")               # 例:
  poc-sales
  WORKTREE_BASE="/workspace/${REPO_NAME}-worktrees" # 例:
  /workspace/poc-sales-worktrees
  ```

  以降のステップでは `$WORKTREE_BASE` と `$REPO_ROOT`
  を使用する。

  ```bash
  # 各 Issue にラベルを付与
  gh issue edit <number> --add-label "claude-in-progress"
  ```

  ※ ラベルがリポジトリに存在しない場合は事前に作成する:
  ```bash
  gh label create "claude-in-progress" --color "FFA500"
  --description "Claude が処理中" 2>/dev/null || true
  gh label create "pr-fix-needed" --color "D93F0B" --description
   "PR のレビュー指摘対応が必要" 2>/dev/null || true
  gh label create "review-addressed" --color "0075CA"
  --description "レビュー指摘対応済み" 2>/dev/null || true
  gh label create "claude-done" --color "0E8A16" --description
  "Claude による対応完了" 2>/dev/null || true
  ```

  ### 通常 Issue の場合

  ```bash
  # 最新の main を取得
  git fetch origin main

  # Issue ごとにworktreeを作成
  git worktree add $WORKTREE_BASE/issue-<number> -b
  issue/<number>-<slug> origin/main
  ```

  スラッグはIssueタイトルから英小文字・数字・ハイフンのみで生成
  する（例: `feat: ユーザー登録` → `user-registration`）。

  ### `pr-fix-needed` Issue の場合

  紐づく PR を検索し、その PR ブランチで worktree を作成する。

  ```bash
  # Issue に紐づく PR を検索
  PR_JSON=$(gh pr list --state open --search "closes #<number>
  OR fixes #<number> OR resolves #<number>" --json
  number,headRefName,url --limit 1)

  # PR が見つからない場合はスキップ（ユーザーに警告表示）
  # 見つかった場合:
  PR_NUMBER=<PR の number>
  PR_BRANCH=<PR の headRefName>

  # PR ブランチで worktree を作成（新ブランチは作らない）
  git fetch origin "$PR_BRANCH"
  git worktree add $WORKTREE_BASE/issue-<number>
  "origin/$PR_BRANCH"
  ```

  全 Issue 分の worktree 作成後、各 worktree
  でサブエージェントを **並列起動** する。

  ## Step 4: サブエージェントを並列起動

  Agent ツールを使って全 Issue
  のサブエージェントを同時に起動する。
  Issue のタイプ（通常 /
  `pr-fix-needed`）に応じて適切なテンプレートを使い分ける。

  ### サブエージェント指示テンプレート（新規実装）

  ```
  あなたは GitHub Issue #<number>
  を担当するサブエージェントです。
  以下のワークツリーで作業してください。

  **重要:
  ユーザーに質問（AskUserQuestion）してはいけません。不明点は
  Issue の内容とコードから自分で判断してください。判断に迷った場
  合は、より安全・シンプルな選択肢を選んでください。**

  ## 作業ディレクトリ
  $WORKTREE_BASE/issue-<number>

  ## Issue 詳細
  <gh issue view <number> の全文をここに貼り付ける>

  ## プロジェクト規約
  $REPO_ROOT/.claude/CLAUDE.md および $REPO_ROOT/CLAUDE.md
  を参照すること。

  ## 作業手順

  ### 1. 実装
  Issue の内容を読んで $WORKTREE_BASE/issue-<number>
  で実装する。

  ### 2. テスト（カバレッジ付き）
  \```bash
  cd $WORKTREE_BASE/issue-<number>
  pnpm run test:coverage 2>&1
  \```
  - 失敗したテストがあれば修正する
  - ファイルごとのカバレッジ 85%
  未達があれば不足テストを追加する
  - 以下を記録しておく:
    - テスト結果: パス数 / 総テスト数
    - カバレッジ（パッケージ別・項目別）: vitest の text
  レポート出力から各パッケージの Stmts / Branch / Funcs / Lines
  % を抽出する

  ### 3. TypeScript 型チェック
  \```bash
  cd $WORKTREE_BASE/issue-<number>
  pnpm run typecheck 2>&1
  \```
  エラーがあれば修正する。結果（エラー数）を記録しておく。

  ### 5. Lint チェック
  \```bash
  cd $WORKTREE_BASE/issue-<number>
  pnpm run lint 2>&1
  \```
  エラーがあれば修正する。結果（エラー数・警告数）を記録しておく
  。

  ### 6. Semgrep セキュリティ静的解析
  \```bash
  cd $WORKTREE_BASE/issue-<number>
  semgrep scan --config auto --error 2>&1
  \```
  - エラー（severity: ERROR）があれば修正する
  - WARNING は内容を確認して対応判断する
  - 結果（findings 数）を記録しておく

  ### 7. Codex レビュー（コミット前・修正必須）
  \```bash
  cd $WORKTREE_BASE/issue-<number>
  codex review --base main --uncommitted 2>&1
  \```
  - 🔴 重大な問題があれば修正してから再度 codex review
  を実行（解消するまでループ）
  - 🟡 改善提案は判断して対応

  ### 8. ブラウザエラーチェック（DoD）
  chrome-devtools MCP の list_console_messages（types: error,
  warn）で、
  変更に関連する画面のエラーを確認する。エラーがあれば修正する。

  ### 9. コミット・プッシュ
  \```bash
  cd $WORKTREE_BASE/issue-<number>
  git add -A
  git commit -m "<Conventional Commits 形式のメッセージ>"
  git push -u origin issue/<number>-<slug>
  \```

  ### 10. PR 作成
  \```bash
  PR_URL=$(gh pr create \
    --title "<Conventional Commits 形式のタイトル>" \
    --body "Closes #<number>

  ## 変更内容
  <箇条書きで変更の概要>

  ---
  🤖 *この PR は Claude によって自動作成されました*" \
    --base main)
  PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')
  \```

  ### 11. Issue にコメント投稿
  \```bash
  gh issue comment <number> --body "## 🤖 対応完了

  ### 変更内容
  <箇条書きで実装内容の要約>

  ### PR
  <PR の URL>

  ---
  *このコメントは Claude によって自動投稿されました*"
  \```

  ### 12. ラベル更新
  \```bash
  gh issue edit <number> --add-label "claude-done"
  --remove-label "claude-in-progress"
  \```

  ### 13. 完了報告
  以下の形式で結果を返す:

  - **PR URL**: <PR の URL>
  - **テスト**: <パス数>/<総テスト数> passed
  - **カバレッジ**:

  | Package | Stmts | Branch | Funcs | Lines |
  |---------|-------|--------|-------|-------|
  | errors  | 95%   | 90%    | 100%  | 95%   |
  | ...     | ...   | ...    | ...   | ...   |

  - **TSC**: <エラー数> errors
  - **Lint**: <エラー数> errors, <警告数> warnings
  - **Semgrep**: <findings 数> findings
  - **実装内容**: <箇条書きで主な変更点>
  ```

  ### サブエージェント指示テンプレート（PR 修正）

  `pr-fix-needed` ラベル付き Issue に使用する。

  ```
  あなたは GitHub Issue #<number> に紐づく PR #<pr_number> 
  の修正を担当するサブエージェントです。
  以下のワークツリーで作業してください。

  **重要: ユーザーに質問（AskUserQuestion）してはいけません。不
  明点はレビューコメント・Issue
  の内容・コードから自分で判断してください。判断に迷った場合は、
  より安全・シンプルな選択肢を選んでください。**

  ## 作業ディレクトリ
  $WORKTREE_BASE/issue-<number>

  ## Issue 詳細
  <gh issue view <number> の全文をここに貼り付ける>

  ## PR レビューコメント
  <gh pr view <pr_number> --comments の内容をここに貼り付ける>

  ## プロジェクト規約
  $REPO_ROOT/.claude/CLAUDE.md および $REPO_ROOT/CLAUDE.md
  を参照すること。

  ## 作業手順

  ### 1. レビューコメントを理解
  PR #<pr_number>
  のレビューコメントを読み、修正が必要な点を把握する。
  \```bash
  gh pr view <pr_number> --json reviews,comments
  gh api repos/{owner}/{repo}/pulls/<pr_number>/comments --jq
  '.[] | {path, body, line, diff_hunk}'
  \```
  各レビューコメントの指摘事項をリスト化する。

  ### 2. 修正
  レビューコメントの指摘に基づいて $WORKTREE_BASE/issue-<number>
   で修正する。

  ### 3. テスト（カバレッジ付き）
  \```bash
  cd $WORKTREE_BASE/issue-<number>
  pnpm run test:coverage 2>&1
  \```
  - 失敗したテストがあれば修正する
  - ファイルごとのカバレッジ 85%
  未達があれば不足テストを追加する
  - 以下を記録しておく:
    - テスト結果: パス数 / 総テスト数
    - カバレッジ（パッケージ別・項目別）: vitest の text
  レポート出力から各パッケージの Stmts / Branch / Funcs / Lines
  % を抽出する

  ### 4. TypeScript 型チェック
  \```bash
  cd $WORKTREE_BASE/issue-<number>
  pnpm run typecheck 2>&1
  \```
  エラーがあれば修正する。結果（エラー数）を記録しておく。

  ### 6. Lint チェック
  \```bash
  cd $WORKTREE_BASE/issue-<number>
  pnpm run lint 2>&1
  \```
  エラーがあれば修正する。結果（エラー数・警告数）を記録しておく
  。

  ### 7. Semgrep セキュリティ静的解析
  \```bash
  cd $WORKTREE_BASE/issue-<number>
  semgrep scan --config auto --error 2>&1
  \```
  - エラー（severity: ERROR）があれば修正する
  - WARNING は内容を確認して対応判断する
  - 結果（findings 数）を記録しておく

  ### 8. Codex レビュー（コミット前・修正必須）
  \```bash
  cd $WORKTREE_BASE/issue-<number>
  codex review --base main --uncommitted 2>&1
  \```
  - 🔴 重大な問題があれば修正してから再度 codex review
  を実行（解消するまでループ）
  - 🟡 改善提案は判断して対応

  ### 9. ブラウザエラーチェック（DoD）
  chrome-devtools MCP の list_console_messages（types: error,
  warn）で、
  変更に関連する画面のエラーを確認する。エラーがあれば修正する。

  ### 10. コミット・プッシュ（既存 PR ブランチへ）& PR
  本文に署名追記
  \```bash
  cd $WORKTREE_BASE/issue-<number>
  git add -A
  git commit -m "fix: PR #<pr_number> レビュー指摘対応"
  git push origin <pr_branch>

  # PR 本文末尾に署名を追記（未付与の場合のみ）
  CURRENT_BODY=$(gh pr view <pr_number> --json body --jq
  '.body')
  if ! echo "$CURRENT_BODY" | grep -q "Claude によって"; then
    gh pr edit <pr_number> --body "${CURRENT_BODY}

  ---
  🤖 *この PR は Claude によって更新されました*"
  fi
  \```
  ※ 新しいブランチは作成しない。既存の PR
  ブランチにプッシュする。

  ### 11. PR にコメント投稿
  \```bash
  gh pr comment <pr_number> --body "## 🤖 レビュー指摘対応完了

  ### 対応内容
  <各レビュー指摘に対する修正内容を箇条書き>

  ---
  *このコメントは Claude によって自動投稿されました*"
  \```

  ### 12. ラベル更新
  \```bash
  gh issue edit <number> --add-label "claude-done"
  --remove-label "claude-in-progress" --remove-label
  "pr-fix-needed" --remove-label "review-complete"
  REPO=$(gh repo view --json nameWithOwner --jq
  '.nameWithOwner')
  gh api "repos/$REPO/issues/<pr_number>/labels" --method POST
  -f 'labels[]=review-addressed'
  \```

  ### 13. 完了報告
  以下の形式で結果を返す:

  - **PR URL**: <PR #pr_number の URL>
  - **テスト**: <パス数>/<総テスト数> passed
  - **カバレッジ**:

  | Package | Stmts | Branch | Funcs | Lines |
  |---------|-------|--------|-------|-------|
  | errors  | 95%   | 90%    | 100%  | 95%   |
  | ...     | ...   | ...    | ...   | ...   |

  - **TSC**: <エラー数> errors
  - **Lint**: <エラー数> errors, <警告数> warnings
  - **Semgrep**: <findings 数> findings
  - **対応内容**: <各レビュー指摘に対する修正を箇条書き>
  ```

  ## Step 5: ラベル除去 & Worktree のクリーンアップ

  全サブエージェントの完了後、worktree を削除する。
  失敗した Issue は `claude-in-progress`
  ラベルを除去する（成功した Issue はサブエージェントが Step 8
  で既にラベル更新済み）。

  ```bash
  # 失敗した Issue のみ: 処理中ラベルを除去
  gh issue edit <number> --remove-label "claude-in-progress"

  # Worktree を削除
  git worktree remove $WORKTREE_BASE/issue-<number> --force
  ```

  ## Step 6: 結果を集約して報告

  ### サマリーテーブル

  | Issue | タイトル | タイプ | 結果 | テスト | TSC | Lint |
  Semgrep | PR |
  |-------|---------|--------|------|--------|-----|------|-----
  ----|----|
  | #N    | ...     | 新規   | 成功 | 35/35  | 0 err | 0 err | 0
   | URL |
  | #N    | ...     | PR修正 | 成功 | 20/20  | 0 err | 0 err | 0
   | URL |
  | #N    | ...     | 新規   | 失敗 | -      | -     | -     | -
   | エラー理由 |

  ### カバレッジ詳細（Issue ごと）

  **#N**

  | Package | Stmts | Branch | Funcs | Lines |
  |---------|-------|--------|-------|-------|
  | errors  | 95%   | 90%    | 100%  | 95%   |
  | ...     | ...   | ...    | ...   | ...   |
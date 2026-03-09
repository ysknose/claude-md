# マージコンフリクト解消ウィザード

git のマージコンフリクトを自動的に解消する。

## Step 1: コンフリクトファイルを特定

```bash
git diff --name-only --diff-filter=U
```

コンフリクトファイルが 0 件の場合は「コンフリクトはありません」と伝えて終了。

## Step 2: コンテキストを把握

```bash
# 現在のブランチと対象ブランチを確認
git status
git log --oneline -5
git log --oneline MERGE_HEAD -5 2>/dev/null || true
```

各ブランチの変更意図を理解する。

## Step 3: コンフリクトを解消

コンフリクトファイルを Read で読み込み、`<<<<<<<` / `=======` / `>>>>>>>` マーカーを確認する。

解消方針:
- **ロジックの競合**: 両方の変更を取り込む形で統合する
- **同一箇所の異なる実装**: どちらが正しいか文脈から判断する。判断できない場合は AskUserQuestion で確認する
- **削除 vs 変更**: 削除側の意図を優先しつつ、変更内容が必要かを判断する

解消後、マーカーが残っていないことを確認する:
```bash
grep -r "<<<<<<\|=======\|>>>>>>>" --include="*.ts" --include="*.tsx" --include="*.js" . 2>/dev/null
```

## Step 4: 動作確認

```bash
# Lint チェック
bun lint 2>/dev/null || npm run lint 2>/dev/null || true

# 型チェック（TypeScript の場合）
bun tsc --noEmit 2>/dev/null || npx tsc --noEmit 2>/dev/null || true
```

エラーがあれば修正する。

## Step 5: ステージング

```bash
git add <解消したファイル>
git status
```

## Step 6: 完了報告

解消したファイル一覧と、各コンフリクトの解消方針を簡潔に報告する。
コミットはユーザーに委ねる（自動でコミットしない）。

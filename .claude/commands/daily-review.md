# デイリーレビュー

その日の作業を振り返り、変更・PR・Issue の状況をまとめる。

## Step 1: 今日の変更を集計

```bash
# 今日コミットされた内容（全ブランチ）
git log --all --since="midnight" --oneline --author="$(git config user.name)" 2>/dev/null

# 未コミットの変更
git status --short
git diff --stat
```

## Step 2: PR・Issue の状況を確認

```bash
# オープン中の自分の PR
gh pr list --author "@me" --state open --json number,title,url,reviewDecision,statusCheckRollup

# 今日マージされた PR
gh pr list --author "@me" --state merged --json number,title,url,mergedAt | jq '[.[] | select(.mergedAt >= (now - 86400 | todate))]' 2>/dev/null || gh pr list --author "@me" --state merged --limit 5 --json number,title,url,mergedAt

# レビュー待ちの PR（自分宛て）
gh pr list --review-requested "@me" --state open --json number,title,url,author
```

## Step 3: サマリーを作成

以下の形式でまとめる:

```
## デイリーレビュー {日付}

### 今日の成果
- マージ済み PR: #N「タイトル」
- コミット数: N件

### 進行中
- PR #N「タイトル」- レビュー待ち / CI待ち / 修正中

### 未コミットの変更
- ファイル名: 変更概要

### レビュー依頼
- PR #N「タイトル」（@author）

### 気づき・メモ
（特記事項があれば）
```

## Step 4: lessons.md への記録

今日の作業で気づいた改善点やパターンがあれば、`tasks/lessons.md` に追記するか確認する。
AskUserQuestion で聞く:
「今日の作業で lessons.md に記録しておくべき気づきはありますか？」

回答があれば `tasks/lessons.md` に追記する。

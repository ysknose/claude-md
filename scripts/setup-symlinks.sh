#!/bin/bash
set -euo pipefail

# ~/.claude/ 以下にシンボリックリンクを作成するスクリプト
# Usage: bash scripts/setup-symlinks.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_CLAUDE_DIR="$(cd "$SCRIPT_DIR/../.claude" && pwd)"
TARGET_DIR="${HOME}/.claude"

# ~/.claude/ が存在しなければ作成
mkdir -p "$TARGET_DIR"

LINKS=(
  "CLAUDE.md"
  "commands"
  "skills"
)

for item in "${LINKS[@]}"; do
  src="$REPO_CLAUDE_DIR/$item"
  dest="$TARGET_DIR/$item"

  if [ ! -e "$src" ]; then
    echo "SKIP: $src が存在しません"
    continue
  fi

  if [ -L "$dest" ]; then
    echo "UPDATE: $dest (既存リンクを上書き)"
  elif [ -e "$dest" ]; then
    echo "BACKUP: $dest -> ${dest}.bak"
    mv "$dest" "${dest}.bak"
  fi

  ln -sf "$src" "$dest"
  echo "OK: $dest -> $src"
done

echo "完了"

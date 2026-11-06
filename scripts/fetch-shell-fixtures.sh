#!/usr/bin/env bash
# Real, pinned prompt-framework fixtures. No user startup files are read or changed.
set -euo pipefail
cd "$(dirname "$0")/.."
source tests-e2e/shell-fixtures.env
target="$PWD/vendor/test-oh-my-zsh"
if [[ ! -d "$target/.git" ]]; then
  mkdir -p "$target"
  git -C "$target" init -q
  git -C "$target" remote add origin https://github.com/ohmyzsh/ohmyzsh.git
fi
git -C "$target" fetch -q --depth 1 origin "$OH_MY_ZSH_COMMIT"
git -C "$target" checkout -q --detach FETCH_HEAD
echo "Oh My Zsh fixture ready at $target ($OH_MY_ZSH_COMMIT)"

#!/usr/bin/env bash
# 启用 GitHub Actions CI（可选）
#
# GitHub 要求令牌具备 `workflow` 权限才能推送 .github/workflows/*.yml。
# 若 gh 使用的 OAuth 令牌没有该权限，先执行：
#     gh auth refresh -s workflow
# 然后运行本脚本：./enable-ci.sh
set -euo pipefail

cd "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f .github/workflows/ci.yml ]; then
  echo "[*] CI 已启用，无需重复操作。"
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "[ERR] 需要 GitHub CLI： https://cli.github.com/" >&2
  exit 1
fi

mkdir -p .github/workflows
cp ci/ci.yml .github/workflows/ci.yml
git add .github/workflows/ci.yml
git commit -m "ci: enable cross-platform self test workflow"

if git push; then
  echo "[OK] CI 已启用，可在仓库 Actions 页查看三平台运行结果。"
else
  echo "[ERR] 推送被拒绝。当前令牌可能缺少 workflow 权限，请执行："
  echo "       gh auth refresh -s workflow"
  echo "       授权后再次运行 ./enable-ci.sh（本次提交已生成，可直接 git push）。"
  exit 1
fi

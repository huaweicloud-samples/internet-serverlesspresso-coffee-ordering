#!/usr/bin/env bash
# ============================================================================
# 构建各函数代码包 → build/<name>.zip
#   - 依赖：nodejs >= 18（打包用 Node 内置 zip.js，无需系统 zip 命令）
#   - 产物：build/auth-register.zip ... build/order-complete.zip（6 个）
#   - 之后由 Terraform（infra/core.tf 的 huaweicloud_obs_bucket_object）上传到 OBS
#
# 每个包的目录结构：
#   index.js                    函数入口（handler = index.handler）
#   order-orchestrator/         公共编排模块（被各函数以 ./order-orchestrator/order-flow 引用）
#   node_modules/               第三方依赖（ioredis / jsonwebtoken）
#
# 用法： ./src/scripts/build-functions.sh
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/src/functions"
DEPS="$ROOT/src/functions/package-deps"
BUILD="$ROOT/build"
STAGE="$BUILD/.stage"

# 函数名 → 入口源文件
declare -A ENTRY=(
  [auth-register]="$SRC/auth/register.js"
  [auth-login]="$SRC/auth/login.js"
  [auth-verify]="$SRC/auth/verify.js"
  [order-create]="$SRC/core/order-create.js"
  [capacity-check]="$SRC/core/capacity-check.js"
  [order-complete]="$SRC/core/order-complete.js"
)

echo "[1/3] 安装第三方依赖（ioredis / jsonwebtoken）"
cd "$DEPS"
rm -rf node_modules
npm install --omit=dev --no-package-lock

echo "[2/3] 打包各函数代码"
rm -rf "$STAGE"
mkdir -p "$STAGE"
for name in "${!ENTRY[@]}"; do
  entry="${ENTRY[$name]}"
  [ -f "$entry" ] || { echo "缺少入口文件: $entry" >&2; exit 1; }

  pkg="$STAGE/$name"
  mkdir -p "$pkg/order-orchestrator"

  # 入口复制为 index.js（handler = index.handler）
  cp "$entry" "$pkg/index.js"

  # 公共编排模块：保持 ./order-orchestrator/order-flow 的相对引用
  cp "$SRC/order-orchestrator/order-flow.js" "$pkg/order-orchestrator/order-flow.js"

  # 第三方依赖
  cp -r "$DEPS/node_modules" "$pkg/node_modules"

  rm -f "$BUILD/$name.zip"
  node "$ROOT/src/scripts/zip.js" "$pkg" "$BUILD/$name.zip"
done

echo "[3/3] 清理暂存目录"
rm -rf "$STAGE"

echo "完成：函数代码包已生成于 $BUILD/"
echo "下一步： cd infra && terraform init && terraform apply -auto-approve"
echo "（Terraform 会自动建桶并把 build/*.zip 上传到 OBS，无需手工 obsutil 上传）"

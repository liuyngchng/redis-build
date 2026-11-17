#!/usr/bin/env bash
# Redis 6.2.6 Docker 镜像构建脚本
# 用法:
#   ./build.sh                                                # 无代理构建
#   ./build.sh http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
#   VERSION=6.2.6 ./build.sh                                    # 通过环境变量指定版本
set -euo pipefail

BUILD_START=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-redis}"

# ── Usage ──
usage() {
  cat <<'EOF'
用法: ./build.sh [proxy...]

参数说明:
  -h | --help             显示本帮助并退出

代理参数（可选，仅构建时使用，不写入镜像）:
  http_proxy=<url>        设置 HTTP  代理
  https_proxy=<url>       设置 HTTPS 代理
  no_proxy=<url>          设置不走代理的地址列表

示例:
  ./build.sh http_proxy=http://127.0.0.1:7890
  ./build.sh https_proxy=http://127.0.0.1:7890 no_proxy=10.0.0.0/8
EOF
}

# ── 参数解析 ──
TAG_VERSION=""
HTTP_PROXY_VAL=""
HTTPS_PROXY_VAL=""
NO_PROXY_VAL=""

for arg in "$@"; do
  case "$arg" in
    http_proxy=*|HTTP_PROXY=*)        HTTP_PROXY_VAL="${arg#*=}" ;;
    https_proxy=*|HTTPS_PROXY=*)      HTTPS_PROXY_VAL="${arg#*=}" ;;
    no_proxy=*|NO_PROXY=*)            NO_PROXY_VAL="${arg#*=}" ;;
    -h|--help|help)                   usage; exit 0 ;;
    -*)                               echo "WARNING: 未知参数 '$arg'，已忽略（用 -h 查看用法）" ;;
    *)                                TAG_VERSION="$arg" ;;
  esac
done

# Resolve version
TAG_VERSION="${TAG_VERSION:-${VERSION:-6.2.6}}"

# 不带 = 时继承环境变量
HTTP_PROXY_VAL="${HTTP_PROXY_VAL:-${HTTP_PROXY:-${http_proxy:-}}}"
HTTPS_PROXY_VAL="${HTTPS_PROXY_VAL:-${HTTPS_PROXY:-${https_proxy:-}}}"
NO_PROXY_VAL="${NO_PROXY_VAL:-${NO_PROXY:-${no_proxy:-}}}"

# 自动补全 scheme
add_scheme() {
  local v="$1"
  [[ -z "$v" || "$v" == *"://"* ]] && { printf '%s' "$v"; return; }
  printf 'http://%s' "$v"
}
HTTP_PROXY_VAL="$(add_scheme "$HTTP_PROXY_VAL")"
HTTPS_PROXY_VAL="$(add_scheme "$HTTPS_PROXY_VAL")"

FULL_TAG="${IMAGE_NAME}:${TAG_VERSION}"

echo "============================================"
echo " Building ${FULL_TAG} (Redis 6.2.6)"
echo "============================================"
if [[ -n "$HTTP_PROXY_VAL" || -n "$HTTPS_PROXY_VAL" ]]; then
  echo " 代理 (仅构建时): http=$HTTP_PROXY_VAL https=$HTTPS_PROXY_VAL no_proxy=$NO_PROXY_VAL"
fi
echo ""

# ---- 准备构建上下文 ----
# 源码 tarball + 配置文件
SOURCE_TARBALL="/media/rd/SD2TB/soft-ubuntu/redis-stable.tar.gz"
SOURCE_DIR="/media/rd/SD2TB/soft-ubuntu/redis-stable"
STAGING_DIR="$SCRIPT_DIR/staging"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# 拷贝源码 tarball
cp "$SOURCE_TARBALL" "$STAGING_DIR/redis-stable.tar.gz"

# 拷贝一份干净的 redis.conf
cp "$SOURCE_DIR/redis.conf" "$STAGING_DIR/redis.conf"

# ---- Docker build args ----
DOCKER_BUILD_ARGS=()
if [[ -n "$HTTP_PROXY_VAL" || -n "$HTTPS_PROXY_VAL" ]]; then
  DOCKER_BUILD_ARGS=(
    --build-arg "HTTP_PROXY=$HTTP_PROXY_VAL"
    --build-arg "HTTPS_PROXY=$HTTPS_PROXY_VAL"
    --build-arg "NO_PROXY=$NO_PROXY_VAL"
  )
fi

# ---- 检查基础镜像 ----
if ! docker image inspect ubuntu:24.04 >/dev/null 2>&1; then
  echo "ERROR: 本地缺少 ubuntu:24.04 基础镜像，请先拉取: docker pull ubuntu:24.04"
  exit 1
fi

# ---- Docker build ----
echo "=== Docker build ==="

docker buildx build \
    "${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"}" \
    -t "${FULL_TAG}" \
    -f "$SCRIPT_DIR/Dockerfile" \
    --load \
    "$STAGING_DIR"

# ---- 清理 ----
rm -rf "$STAGING_DIR"

# Remove dangling images + buildx cache
echo ""
echo "=== 清理 dangling 镜像 ==="
docker image prune -f --filter "dangling=true" || true
docker builder prune -f --max-storage 2GB || true

BUILD_ELAPSED=$(( $(date +%s) - BUILD_START ))
echo "============================================"
echo " Build complete: ${FULL_TAG}"
printf " 总耗时: %dm %ds\n" $(( BUILD_ELAPSED / 60 )) $(( BUILD_ELAPSED % 60 ))
echo "============================================"
echo ""
echo "启动 Redis 容器示例:"
echo "  docker run -d --name redis -p 6379:6379 ${FULL_TAG}"
echo ""
echo "使用自定义配置文件:"
echo "  docker run -d --name redis -v \$(pwd)/redis.conf:/etc/redis/redis.conf \\"
echo "    -p 6379:6379 ${FULL_TAG}"
echo ""
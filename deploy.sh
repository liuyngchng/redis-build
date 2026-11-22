#!/usr/bin/env bash
# Redis 6.2.6 — 部署脚本（docker run 封装，支持 auth 密码）
#
# 用法:
#   ./deploy.sh up            # 启动（若设置了 REDIS_PASSWORD 则自动开启认证）
#   ./deploy.sh down          # 停止并移除容器
#   ./deploy.sh restart       # 重启
#   ./deploy.sh logs          # 查看日志
#   ./deploy.sh ps            # 查看容器状态
#   ./deploy.sh ping          # 连通性检查（自动带密码）
#   ./deploy.sh cli           # 进入 redis-cli（自动带密码）
#   ./deploy.sh gen-token     # 生成随机 auth 密码并写入 .redis-env
#
# 环境变量（均可被同名环境变量覆盖）:
#   IMAGE_TAG       镜像版本（默认 6.2.6）
#   CONTAINER_NAME  容器名（默认 redis）
#   REDIS_PORT      宿主机端口（默认 6379）
#   REDIS_PASSWORD  redis 认证密码（默认空 = 不启用认证）
#   DATA_DIR        宿主机数据目录（默认 ./data，持久化 AOF/RDB）
#   REDIS_CONF      自定义 redis.conf 路径（默认空 = 用镜像内置配置）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.redis-env"

# ── 工具函数 ────────────────────────────────────────────────────
msg()  { printf '\n\033[1;32m[deploy]\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m[deploy]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m[deploy]\033[0m %s\n' "$*" >&2; exit 1; }

load_env() {
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    set -a; . "$ENV_FILE"; set +a
  fi
}

require_image() {
  local tag="${IMAGE_TAG:-6.2.6}"
  if ! docker image inspect "redis:$tag" >/dev/null 2>&1; then
    die "镜像 redis:$tag 不存在。请先执行 ./build.sh 构建镜像。"
  fi
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -qx "$1"
}

container_running() {
  docker ps --format '{{.Names}}' | grep -qx "$1"
}

# 生成 redis-cli 认证参数（有密码时返回 "-a <password>"）
cli_auth_args() {
  if [ -n "${REDIS_PASSWORD:-}" ]; then
    printf '%s' "-a $REDIS_PASSWORD"
  fi
}

# ── 子命令 ──────────────────────────────────────────────────────
cmd_gen_token() {
  if [ -f "$ENV_FILE" ] && grep -q '^REDIS_PASSWORD=' "$ENV_FILE" 2>/dev/null; then
    warn "$ENV_FILE 已存在 REDIS_PASSWORD，跳过生成"
    cat "$ENV_FILE"
    return 0
  fi
  local token
  token=$(openssl rand -hex 32 2>/dev/null || head -c32 /dev/urandom | od -An -tx1 | tr -d ' \n')
  printf 'REDIS_PASSWORD=%s\n' "$token" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  msg "已生成 redis auth 密码并写入 $ENV_FILE（权限 600）"
  echo ""
  echo "  deploy.sh 会自动加载该文件。需要改密码时，删除该文件后重新 gen-token，"
  echo "  或手动编辑 $ENV_FILE。"
  echo ""
  cat "$ENV_FILE"
}

cmd_up() {
  load_env
  require_image

  local image_tag="${IMAGE_TAG:-6.2.6}"
  local name="${CONTAINER_NAME:-redis}"
  local port="${REDIS_PORT:-6379}"
  local data_dir="${DATA_DIR:-$SCRIPT_DIR/data}"

  if container_exists "$name"; then
    if container_running "$name"; then
      die "容器 $name 已在运行。如需重建请先执行: ./deploy.sh down"
    fi
    warn "容器 $name 已存在但未运行，将移除后重建"
    docker rm -f "$name" >/dev/null
  fi

  # 自定义配置检查
  local conf_mount=()
  if [ -n "${REDIS_CONF:-}" ]; then
    [ -f "$REDIS_CONF" ] || die "自定义配置文件不存在: $REDIS_CONF"
    conf_mount=(-v "$REDIS_CONF:/etc/redis/redis.conf:ro")
  fi

  mkdir -p "$data_dir"

  # redis-server 命令：内置配置为基，密码通过命令行追加（覆盖配置文件）
  local cmd=(redis-server /etc/redis/redis.conf)
  if [ -n "${REDIS_PASSWORD:-}" ]; then
    cmd+=(--requirepass "$REDIS_PASSWORD")
  fi

  msg "启动 $name (镜像 redis:$image_tag, 端口 ${port}:6379)"
  docker run -d \
    --name "$name" \
    --restart unless-stopped \
    -p "${port}:6379" \
    -v "$data_dir:/data" \
    "${conf_mount[@]+"${conf_mount[@]}"}" \
    "redis:$image_tag" \
    "${cmd[@]}" >/dev/null

  echo "  容器:     $name"
  echo "  端口:     ${port}->6379"
  echo "  数据目录: $data_dir"
  if [ -n "${REDIS_PASSWORD:-}" ]; then
    echo "  认证:     已启用 (REDIS_PASSWORD)"
  else
    warn "  认证:     未启用（未设置 REDIS_PASSWORD）"
  fi
  echo ""
  echo "  验证:     ./deploy.sh ping"
  echo "  连接:     ./deploy.sh cli"
}

cmd_down() {
  load_env
  local name="${CONTAINER_NAME:-redis}"
  if container_exists "$name"; then
    msg "停止并移除容器 $name"
    docker rm -f "$name" >/dev/null
    echo "  已移除 $name（数据目录未被删除）"
  else
    warn "容器 $name 不存在"
  fi
}

cmd_restart() {
  load_env
  local name="${CONTAINER_NAME:-redis}"
  if ! container_running "$name"; then
    die "容器 $name 未在运行，请先执行: ./deploy.sh up"
  fi
  msg "重启 $name"
  docker restart "$name"
}

cmd_logs() {
  load_env
  local name="${CONTAINER_NAME:-redis}"
  container_exists "$name" || die "容器 $name 不存在"
  docker logs -f --tail=100 "$name"
}

cmd_ps() {
  load_env
  local name="${CONTAINER_NAME:-redis}"
  docker ps -a --filter "name=^${name}$"
}

cmd_ping() {
  load_env
  local name="${CONTAINER_NAME:-redis}"
  container_running "$name" || die "容器 $name 未在运行"
  local auth
  auth="$(cli_auth_args)"
  # shellcheck disable=SC2086
  docker exec "$name" redis-cli $auth ping
}

cmd_cli() {
  load_env
  local name="${CONTAINER_NAME:-redis}"
  container_running "$name" || die "容器 $name 未在运行"
  local auth
  auth="$(cli_auth_args)"
  # shellcheck disable=SC2086
  exec docker exec -it "$name" redis-cli $auth
}

# ── 入口 ────────────────────────────────────────────────────────
cmd="${1:-}"
shift || true
case "$cmd" in
  up)        cmd_up ;;
  down)      cmd_down ;;
  restart)   cmd_restart ;;
  logs)      cmd_logs ;;
  ps|status) cmd_ps ;;
  ping)      cmd_ping ;;
  cli)       cmd_cli ;;
  gen-token) cmd_gen_token ;;
  -h|--help|help)
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    echo "用法: $0 [up|down|restart|logs|ps|ping|cli|gen-token]" >&2
    exit 1
    ;;
esac

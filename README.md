# Redis 6.2.6 Docker 镜像

基于 `ubuntu:24.04` 从源码编译的 Redis 6.2.6 镜像，运行用户为 `redis`（uid=999，非 root）。

## 目录结构

```
redis-build/
├── Dockerfile    # 多阶段构建：Stage1 编译，Stage2 精简运行镜像（无代理、无编译工具）
├── build.sh      # 构建脚本
├── deploy.sh     # 部署脚本（支持 auth 密码、持久化、自定义配置）
└── README.md
```

## 构建

```bash
# 无代理构建
./build.sh

# 需要代理时（仅构建期使用，不会写入镜像）
./build.sh http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
```

> 代理通过 `--build-arg` 传入，只在 Stage 1 安装编译工具时生效，最终镜像内**不含任何代理环境变量**。

产物：`redis:6.2.6`。

## 部署（推荐）

使用 `deploy.sh`，支持 auth 密码、持久化、自定义配置。

```bash
# 1. 生成随机 auth 密码（写入 .redis-env，deploy.sh 自动加载）
./deploy.sh gen-token

# 2. 启动（自动开启认证、持久化到 ./data、端口 6379）
./deploy.sh up

# 3. 验证
./deploy.sh ping          # PONG

# 4. 进入 redis-cli（自动带密码）
./deploy.sh cli
```

常用命令：

```bash
./deploy.sh logs          # 查看日志
./deploy.sh restart       # 重启
./deploy.sh ps            # 查看容器状态
./deploy.sh down          # 停止并移除容器（数据保留）
```

### 可用环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `IMAGE_TAG` | `6.2.6` | 镜像版本 |
| `CONTAINER_NAME` | `redis` | 容器名 |
| `REDIS_PORT` | `6379` | 宿主机端口 |
| `REDIS_PASSWORD` | 空 | redis 认证密码（空=不启用认证） |
| `DATA_DIR` | `./data` | 宿主机数据目录 |
| `REDIS_CONF` | 空 | 自定义 redis.conf 路径 |

```bash
# 自定义端口、数据目录
REDIS_PORT=6380 DATA_DIR=/srv/redis ./deploy.sh up

# 手动指定密码（不生成随机密码）
REDIS_PASSWORD='你的密码' ./deploy.sh up
```

> `gen-token` 生成的密码会写入 `.redis-env`（权限 600），被 `deploy.sh` 自动加载。

## 手动启动（不用 deploy.sh）

### 1. 最简单方式

```bash
docker run -d --name redis -p 6379:6379 redis:6.2.6
```

### 2. 挂载自定义配置

```bash
docker run -d --name redis \
  -p 6379:6379 \
  -v $(pwd)/redis.conf:/etc/redis/redis.conf \
  redis:6.2.6
```

### 3. 持久化数据

```bash
docker run -d --name redis \
  -p 6379:6379 \
  -v /srv/redis/data:/data \
  redis:6.2.6
```

> 镜像已声明 `VOLUME ["/data"]`，AOF/RDB 默认写入 `/data`。

### 4. 设置密码（redis 6.2 已默认开启 protected-mode）

```bash
docker run -d --name redis \
  -p 6379:6379 \
  redis:6.2.6 redis-server --requirepass '你的密码'
```

## 验证

```bash
# 无密码
docker exec redis redis-cli ping          # 期望输出 PONG

# 有密码
docker exec redis redis-cli -a '你的密码' ping
```

## 常用操作

```bash
# 查看日志
docker logs -f redis

# 进入 redis-cli
docker exec -it redis redis-cli

# 停止 / 启动 / 删除
docker stop redis
docker start redis
docker rm -f redis
```

## 镜像说明

| 项目 | 内容 |
|---|---|
| 基础镜像 | `ubuntu:24.04` |
| Redis 版本 | 6.2.6（本地 tarball 源码编译） |
| 内存分配器 | libc (glibc malloc) |
| 运行用户 | `redis` (uid=999, nologin) |
| 数据目录 | `/data` |
| 配置文件 | `/etc/redis/redis.conf` |
| 监听端口 | `6379` |
| 内置工具 | redis-server / redis-cli / redis-benchmark / redis-sentinel / redis-check-rdb / redis-check-aof |

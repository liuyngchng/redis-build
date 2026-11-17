# ============================================================================
# Stage 1 - build redis from source (proxy only used here)
# ============================================================================
FROM ubuntu:24.04 AS builder

ARG HTTP_PROXY=""
ARG HTTPS_PROXY=""
ARG NO_PROXY=""
ARG http_proxy="$HTTP_PROXY"
ARG https_proxy="$HTTPS_PROXY"
ARG no_proxy="$NO_PROXY"

# 仅构建期使用代理；装完编译工具后立即删除 apt 代理配置
RUN if [ -n "$HTTP_PROXY" ]; then \
        echo 'Acquire::http::Proxy "'$HTTP_PROXY'";' > /etc/apt/apt.conf.d/01proxy; \
    fi; \
    if [ -n "$HTTPS_PROXY" ]; then \
        echo 'Acquire::https::Proxy "'$HTTPS_PROXY'";' >> /etc/apt/apt.conf.d/01proxy; \
    fi

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential pkg-config ca-certificates \
    && rm -f /etc/apt/apt.conf.d/01proxy

# 源码从本地 tarball 拷入
COPY redis-stable.tar.gz /tmp/
RUN tar -xzf /tmp/redis-stable.tar.gz -C /tmp \
    && rm /tmp/redis-stable.tar.gz

WORKDIR /tmp/redis-stable
# 禁用 jemalloc(需额外内联汇编/兼容性)，统一用 glibc malloc；-j 与 buildkit 缓存无关
RUN make -j"$(nproc)" BUILD_TLS=no MALLOC=libc \
    && make install PREFIX=/opt/redis

# ============================================================================
# Stage 2 - final runtime image (no proxy, no build tools)
# ============================================================================
FROM ubuntu:24.04

# 这里刻意不声明任何 HTTP_PROXY / http_proxy ARG/ENV，保证镜像内无代理环境变量
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Asia/Shanghai \
    REDIS_VERSION=6.2.6

# 仅安装运行所需的最小依赖（redis 运行不需要额外库，装 ca-certificates 备用 TLS/出网）
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 运行用户
RUN useradd -r -M -s /usr/sbin/nologin -u 999 redis

# 编译产物 + 配置 + 数据目录
COPY --from=builder /opt/redis/bin/ /usr/local/bin/
RUN mkdir -p /data /etc/redis && chown -R redis:redis /data /etc/redis

# 默认配置（生产建议挂载覆盖；redis 6.2 已默认 protected-mode yes）
COPY redis.conf /etc/redis/redis.conf
RUN chown redis:redis /etc/redis/redis.conf

USER redis
WORKDIR /data
VOLUME ["/data"]

EXPOSE 6379

CMD ["redis-server", "/etc/redis/redis.conf"]

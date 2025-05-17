# 使用多阶段构建减小镜像体积
FROM alpine:3.18 AS builder

# 安装编译依赖
RUN apk add --no-cache \
    build-base \
    pcre-dev \
    openssl-dev \
    zlib-dev \
    git

# 下载 Nginx 和模块源码
RUN git clone https://github.com/winshining/nginx-http-flv-module.git && \
    wget http://nginx.org/download/nginx-1.25.3.tar.gz && \
    tar -zxvf nginx-1.25.3.tar.gz

# 编译 Nginx (包含 RTMP 和 FLV 模块)
WORKDIR /nginx-1.25.3
RUN ./configure \
    --prefix=/usr/local/nginx \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_realip_module \
    --with-http_auth_request_module \
    --with-http_v2_module \
    --with-http_dav_module \
    --with-http_slice_module \
    --with-threads \
    --with-http_addition_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module\
    --add-module=../nginx-http-flv-module && \
    make -j$(nproc) && \
    make install

# 构建最终镜像
FROM alpine:3.18
COPY --from=builder /usr/local/nginx /usr/local/nginx

# 安装运行时依赖
RUN apk add --no-cache pcre openssl zlib && \
    mkdir -p /tmp/hls /var/log/nginx && \
    chmod 755 /tmp/hls && \
    rm -rf /var/cache/apk/*
    
# 设置环境变量
ENV PATH="/usr/local/nginx/sbin:${PATH}" \
    NGINX_LOG_DIR="/var/log/nginx"
    
# 暴露端口
EXPOSE 1935 80 443

# 启动命令
CMD ["/usr/local/nginx/sbin/nginx", "-g", "daemon off;"]

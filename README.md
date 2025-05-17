# 如何使用？




# 以下为历程记录
## 安装docker

虚拟机 ubuntu 22.04 安装 docker

```
#安装前先卸载操作系统默认安装的docker，
sudo apt-get remove docker docker-engine docker.io containerd runc

#安装必要支持
sudo apt install apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release
```



```
#添加 Docker 官方 GPG key （可能国内现在访问会存在问题）
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 阿里源（推荐使用阿里的gpg KEY）
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

#添加 apt 源:
#Docker官方源
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null


#阿里apt源
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

#更新源
sudo apt update
sudo apt-get update
```



```
#安装最新版本的Docker
sudo apt install docker-ce docker-ce-cli containerd.io
#等待安装完成

#查看Docker版本
sudo docker version

#查看Docker运行状态
sudo systemctl status docker
```

此时使用 docker ps 会提示权限不够，需要 sudo docker ps

```
#添加docker用户组
sudo groupadd docker

#将当前用户添加到用户组
sudo usermod -aG docker $USER

#使权限生效
newgrp docker

#查看所有容器
docker ps -a


```

如果没有此行命令，你会发现，当你每次打开新的终端
你都必须先执行一次 “newgrp docker” 命令
否则当前用户还是不可以执行docker命令

```
gedit ~/.bashrc
# 在文件最下方加入
if ! groups | grep -q docker; then
    newgrp docker
fi

```

另外，我们需要在docker daemon 配置文件中增加国的可用的 docker hub mirror ，

找到你的daemon.json 文件，通常在 /etc/docker/daemon.json 这个位置，如果没有就创建一个

```
sudo gedit /etc/docker/daemon.json
```

在daemon.json 中增加

```
{
    "registry-mirrors": [
        "https://docker.m.daocloud.io"
  ]
}
```

重置生效

```
sudo systemctl daemon-reload
```

```
sudo systemctl restart docker
```

```
docker info
```

如果中途出错可以，执行以下命令卸载docker，重试

```
sudo apt-get purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```



## 搭建Nginx-RTMP 

### 准备工作

在docker 上搭建 Nginx-RTMP 

拉取镜像

```
docker pull tiangolo/nginx-rtmp:latest

#查看
docker images
```

使用Docker命令运行Nginx-RTMP容器，并映射好必要的端口（如RTMP协议的1935端口和HTTP协议的80端口）。

```
docker run -d -p 1935:1935 -p 80:80 --name nginx-rtmp tiangolo/nginx-rtmp:latest
```

直接在容器中修改配置文件，可能会由于容器重启或删除而失效。故采用-v挂载的方式。

为了综合管理以后的多个docker容器，在本地ubuntu中创建以下文件结构，以后将这些目录挂载到docker容器上。

```
mkdir -p \
  ~/Desktop/docker/projects/nginx-rtmp/{config,data/hls,data/recordings,dist,logs}
  
  
/home/lzk/Desktop/docker/
├── projects/                    # 所有Docker项目
   ├── nginx-rtmp/               # 流媒体服务
          ├── config/            # Nginx配置
          │   └── nginx.conf
          ├── data/              # 持久化数据
          │   ├── hls/           # HLS切片
          │   └── recordings/    # 录像文件
          ├── logs/              # 日志文件
          ├── dist/              # 前端编译后的静态文件
          └── docker-compose.yml         # 主编排文件
```

复制配置文件

```
docker cp nginx-rtmp:/etc/nginx/nginx.conf ~/Desktop/docker/projects/nginx-rtmp/config/

# 删除这个容器，后面再启动
docker rm -f nginx-rtmp
```

### 修改nignx.conf配置文件

```
worker_processes auto;

events {
    worker_connections 1024;
    use epoll;
}

rtmp {
    server {
        listen 1935;
        chunk_size 8192;
        max_streams 64;
        ack_window 5000000;  # 合理ACK窗口大小
        
        application live {
            live on;
            meta off;         # 禁用元数据缓存
            
            # HLS低延迟优化
            hls on;
            hls_path /tmp/hls;
            hls_fragment 1s;     # 切片时长1s
            hls_playlist_length 3s; # 播放列表保留3秒切片
            hls_sync 100ms;         # 音视频同步阈值
            hls_base_url /hls/;  # HLS访问路径
            
            # 关键帧间隔优化
            wait_key off;    # 不等待关键帧
            idle_streams off;
          
        }
    }
}

http {
    include mime.types;
    default_type application/octet-stream;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;

    server {
        listen 80;
        server_name localhost;
	
	root /usr/share/nginx/html;  # 必须与挂载路径一致
        index index.html;
        
        location / {
            try_files $uri $uri/ /index.html;
        }
        
        # HLS端点（极低延迟配置）
        location /hls {
            alias /tmp/hls;
            types {
                application/vnd.apple.mpegurl m3u8;
                video/mp2t ts;
            }
        }
	
        # 状态监控端点
        location /stat {
            rtmp_stat all;
            rtmp_stat_stylesheet stat.xsl;
        }
        location /stat.xsl {
            root /usr/local/nginx/conf;
        }
    }
}
```

### index.html

```
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>直播监控</title>
    <link href="/css/video-js.min.css" rel="stylesheet">
</head>
<body>
    <!-- HLS播放器 -->
    <div style="margin:20px;">
        <h3>HLS直播流</h3>
        <video id="hlsPlayer" class="video-js vjs-default-skin" controls width="1024" height="576">
            <source src="/hls/stream.m3u8" type="application/vnd.apple.mpegurl">
        </video>
    </div>

    <!-- 依赖库 -->
    <script src="/js/video.min.js"></script>
    <script>
        // HLS播放器初始化
        const hlsPlayer = videojs('hlsPlayer', {
            autoplay: true,
            fluid: true,
            techOrder: ['html5']  // 强制使用HTML5模式
        });

    </script>
</body>
</html>
```



### 编写 docker-compose.yml

```
services:
  nginx-rtmp:
    image: tiangolo/nginx-rtmp:latest
    container_name: nginx-rtmp
    restart: unless-stopped
    ports:
      - "1935:1935"  # RTMP协议端口
      - "80:80"      # HTTP协议端口
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf     # 配置文件
      - ./data/hls:/tmp/hls                          # HLS切片存储
      - ./data/recordings:/tmp/recordings            # 录像文件存储
      - ./logs:/var/log/nginx                        # 日志文件
      - ./dist:/usr/share/nginx/html                 # 前端编译文件
    environment:
      - TZ=Asia/Shanghai                             # 时区设置
```

启动服务

```
# 安装docker-compose
sudo apt  install docker-compose

# 进入项目目录
cd ~/Desktop/docker/projects/nginx-rtmp

# 启动容器（后台模式）
docker compose up -d

# 查看运行状态
docker-compose ps
# 应显示状态为 Up

# 如果修改了本地文件则需要重新启动
docker compose down -v && docker compose up -d
```

验证挂载结果

```
# 检查配置文件同步
docker exec nginx-rtmp ls -l /etc/nginx/
# 应看到nginx.conf的修改时间为当前时间

# 查看HLS目录权限
docker exec nginx-rtmp ls -ld /tmp/hls
# 应显示权限为 drwxr-xr-x

# 验证dist文件挂载
docker exec nginx-rtmp ls /usr/share/nginx/html
```

ubuntu主机开放端口

```
sudo ufw allow 80/tcp
sudo ufw allow 1935/tcp
sudo ufw reload
```

###  推流测试

命令行形式：

```
# 延迟 45 秒
ffmpeg -f v4l2 -input_format yuyv422 -i /dev/video0 \
  -c:v libx264 -preset ultrafast -tune zerolatency \
  -f flv rtmp://192.168.217.130/live/stream
```

使用脚本，创建 push_stream.sh

```
#!/bin/bash

INPUT_DEVICE="/dev/video0"
RTMP_URL="rtmp://192.168.217.130/live/stream"
  
ffmpeg \
  -f v4l2 \
  -input_format yuyv422 \
  -video_size 640x480 \
  -framerate 30 \
  -i "$INPUT_DEVICE" \
  -vf "format=yuv420p" \
  -c:v libx264 \
  -profile:v baseline \
  -level 3.1 \
  -preset ultrafast \
  -tune zerolatency \
  -x264-params "keyint=30:min-keyint=30:no-scenecut=1" \
  -b:v 1M \
  -maxrate 1M \
  -minrate 1M \
  -f flv \
  "$RTMP_URL"
```

进入浏览器查看

```
http://localhost:80
```

## 搭建nginx-FLV

由于之前是拉取的 nginx-rtmp 的镜像，不支持flv。所以需要重新构建一个支持flv的nginx镜像。

nginx-http-flv-module 支持flv且具备 nginx-rtmp-module的功能。

依然采用挂载的方式，在虚拟机本地创建目录

```
mkdir -p \
  ~/Desktop/docker/projects/nginx-flv/{config,data/hls,data/recordings,dist,logs,certs}
  
```

开启HTTPS 服务生成，自签名证书

```
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certs/key.pem \
  -out certs/cert.pem \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:192.168.217.130"
```

编写Dockerfile

```
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
```

构建镜像

```
docker build -t nginx-flv .
```

编写nginx.conf

```
worker_processes auto;

events {
    worker_connections 1024;
    use epoll;
}
http {
    include mime.types;
    default_type application/octet-stream;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;

    server {
     	listen 443 ssl;  # 启用 HTTPS
        ssl_certificate      /etc/nginx/certs/cert.pem;
        ssl_certificate_key  /etc/nginx/certs/key.pem;
        root /usr/share/nginx/html;
        index index.html;
        
        location / {
            root /usr/share/nginx/html;
            try_files $uri $uri/ /index.html;
        }
        # HLS 端点
        location /hls {
            alias /tmp/hls;
	    types {
		application/vnd.apple.mpegurl m3u8;
		video/mp2t ts;
	    }
	    add_header Cache-Control no-cache;
	    add_header Access-Control-Allow-Origin *;
	    add_header Access-Control-Allow-Methods GET,OPTIONS;
	    add_header Access-Control-Allow-Headers *;
        }


        # HTTP-FLV 播放端点
        location /live {
            flv_live on;
	    add_header Access-Control-Allow-Origin *;
	    add_header Access-Control-Allow-Methods GET,OPTIONS;
	    add_header Access-Control-Allow-Headers *;
	    add_header Access-Control-Allow-Credentials true;
	    chunked_transfer_encoding on;
        }

        # 状态监控端点
        location /stat {
            rtmp_stat all;
            rtmp_stat_stylesheet stat.xsl;
        }
        location /stat.xsl {
            root /usr/local/nginx/conf;
        }
    }
    server {
        listen 80;
        server_name localhost;
        return 301 https://$host$request_uri;  # HTTP 强制跳转 HTTPS
    }
}

rtmp_auto_push on;
rtmp_auto_push_reconnect 1s;
rtmp {
    out_queue           4096;
    out_cork            8;
    max_streams         128;
    timeout             15s;
    drop_idle_publisher 15s;

    log_interval 5s; #log模块在access.log中记录日志的间隔时间，对调试非常有用
    log_size     1m; #log模块用来记录日志的缓冲区大小
    server {
        listen 1935;
        chunk_size 4096;
        ping 30s;
        notify_method get;

        application live {
            live on;
            meta off;
            
            # HLS 配置
            hls on;
            hls_path /tmp/hls;
            hls_fragment 2s;       # 切片时长至少1秒，建议2秒
            hls_playlist_length 6s; # 播放列表保留3个切片
            hls_sync 100ms;
            hls_base_url /hls/;
            hls_cleanup on;       # 自动清理旧切片
            hls_continuous on;    # 连续模式（避免播放中断）
        }
    }
}


```

编写 index.html

```
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>直播监控</title>
    <link href="/css/video-js.min.css" rel="stylesheet">
	<style>
        /* 容器样式 */
        .player-container {
            display: flex;
            gap: 20px; /* 播放器间距 */
            padding: 20px;
            max-width: 1600px; /* 最大宽度限制 */
            margin: 0 auto; /* 居中 */
        }

        /* 单个播放器包装 */
        .player-wrapper {
            flex: 1; /* 等分剩余空间 */
            min-width: 300px; /* 最小宽度防止挤压 */
            background: #f5f5f5;
            border-radius: 8px;
            padding: 15px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }

        /* 视频元素自适应 */
        .video-js, #videoElement {
            width: 100%;
            height: auto;
            border-radius: 4px;
        }

        /* 标题样式 */
        h3 {
            margin: 0 0 10px 0;
            color: #333;
            font-size: 1.2em;
            text-align: center;
        }

        /* 移动端适配 */
        @media (max-width: 768px) {
            .player-container {
                flex-direction: column; /* 小屏幕垂直排列 */
            }
        }
    </style>
</head>
<body>
    <!-- 播放器容器 -->
    <div class="player-container">
        <!-- HLS 播放器 -->
        <div class="player-wrapper">
            <h3>HLS 直播流</h3>
            <video id="hlsPlayer" class="video-js vjs-default-skin" controls>
                <source src="/hls/stream.m3u8" type="application/vnd.apple.mpegurl">
            </video>
        </div>

        <!-- FLV 播放器 -->
        <div class="player-wrapper">
            <h3>FLV 低延迟流</h3>
            <video id="videoElement" controls></video>
        </div>
    </div>

    <!-- 依赖库 -->
    <script src="/js/video.min.js"></script>
        <script src="/js/flv.min.js"></script>
    <script>
        // HLS播放器初始化
        const hlsPlayer = videojs('hlsPlayer', {
            autoplay: true,
            fluid: true,
            techOrder: ['html5']  // 强制使用HTML5模式
        });
        // flv播放器初始化
        const videoElement = document.getElementById('videoElement');
        const flvPlayer = flvjs.createPlayer({
	    type: 'flv',
	    url: '/live?app=live&stream=stream',
	    isLive: true,
	    hasAudio: false,
	    stashInitialSize: 128,
	    withCredentials: true  // 允许跨域带凭证
	});
        flvPlayer.attachMediaElement(videoElement);
        flvPlayer.load();
        flvPlayer.play();
    </script>
</body>
</html>
```

使用docker compose构建容器

```
services:
  nginx-flv:
    image: nginx-flv:latest
    container_name: nginx-flv
    restart: unless-stopped
    ports:
      - "1935:1935"  # RTMP协议端口
      - "80:80"      # HTTP协议端口
      - "443:443"
    volumes:
      - ./config/nginx.conf:/usr/local/nginx/conf/nginx.conf  # 修正配置文件路径
      - ./data/hls:/tmp/hls
      - ./data/recordings:/tmp/recordings
      - ./logs:/var/log/nginx
      - ./dist:/usr/share/nginx/html  # 静态文件目录
      - ./certs:/etc/nginx/certs  # 挂载证书目录
    environment:
      - TZ=Asia/Shanghai
```

使用ffmpeg进行推流

```
#!/bin/bash

# 推流参数配置
INPUT_DEVICE="/dev/video0"                              # 摄像头设备
RTMP_URL="rtmp://192.168.217.130/live/stream"       # 流名称需匹配前端播放器
RESOLUTION="640x480"                                   # 建议分辨率
FPS=15                                                  # 帧率
BITRATE="2000k"                                         # 码率

ffmpeg \
  -f v4l2 \
  -input_format yuyv422 \
  -video_size $RESOLUTION \
  -framerate $FPS \
  -i "$INPUT_DEVICE" \
  -vf "format=yuv420p" \
  -c:v libx264 \
  -profile:v main \
  -preset ultrafast \
  -tune zerolatency \
  -x264-params "keyint=60:min-keyint=30:no-scenecut=1" \
  -b:v $BITRATE \
  -maxrate $BITRATE \
  -minrate $BITRATE \
  -f flv \
  "$RTMP_URL"
```

运行容器

```
docker compose up -d

#删除并运行（更新文件后）
docker compose down -v && docker compose up -d
```



## 有哪些坑？

> `访问页面只显示nginx的官方页面，自己的index.html未生效，但是已经挂载了(可以进入容器内查看)` ---> 文件或文件夹权限问题。
>
> ```
> # 进入容器检查挂载目录
> docker exec -it nginx-flv ls -l /usr/share/nginx/html
> 
> # 预期输出
> total 12
> -rw-r--r-- 1 root root  537 index.html
> drwxr-xr-x 2 root root 4096 css
> drwxr-xr-x 2 root root 4096 js
> 
> # 修补措施
> # 在宿主机执行（假设挂载目录为 ./html）
> chmod -R 755 ./html      # 目录权限
> find ./html -type f -exec chmod 644 {} \;  # 文件权限
> ```

> `如果docker ps 后发现没有端口信息，应该是出错了。使用 docker logs 容器id 查看错误信息`
>
> 例如
>
> ![image-20250517161421511](https://zikcc.oss-cn-beijing.aliyuncs.com/img/202505171614609.png)

> index.html文件中的视频地址如果采用ip+路径的形式，会存在跨域问题，为了简单，直接使用了相对地址

## 
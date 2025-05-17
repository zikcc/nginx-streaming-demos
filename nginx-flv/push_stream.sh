#!/bin/bash

# 推流参数配置
INPUT_DEVICE="/dev/video0"                              # 摄像头设备
RTMP_URL="rtmp://192.168.217.130/live/stream"       	# 流名称需匹配前端播放器
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

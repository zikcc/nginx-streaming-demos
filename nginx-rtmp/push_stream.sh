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

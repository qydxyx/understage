---
id: ffmpeg
title: FFmpeg recipes
match: mp4,mov,mkv,m4v,avi,webm,mp3,wav,m4a,aac,gif
---

Prefer `/opt/homebrew/bin/ffmpeg` then `/usr/local/bin/ffmpeg`. Never overwrite; pick `name_1.ext`.

- 1080p H.264: `-vf scale=-2:1080 -c:v libx264 -c:a aac -pix_fmt yuv420p`
- Extract audio AAC: `-vn -c:a aac`
- Strip audio: `-c:v copy -an`
- GIF: `-vf fps=12,scale=640:-1`
- Always `-hide_banner -nostdin`. No `-y` unless the destination is a new unique path.

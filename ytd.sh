#!/usr/bin/env bash

URL="$1"
MODE="$2"

case "$MODE" in
    c|C)
        # Audio with cropped square thumbnail
        yt-dlp -f 251 -x --audio-format mp3 \
            --extractor-args "youtube:player-client=web_embedded,tv" \
            --embed-thumbnail --embed-metadata \
            --ppa "ThumbnailsConvertor+ffmpeg:-c:v mjpeg -vf crop='ih:ih'" \
            --ppa "EmbedThumbnail+ffmpeg:-c:a copy" \
            -o "%(title)s - %(uploader)s" \
            "$URL"
        ;;
    v|V)
        # Video download
        yt-dlp -f 136+140 \
            --extractor-args "youtube:player-client=web_embedded,tv" \
            --embed-thumbnail --embed-metadata \
            --ppa "EmbedThumbnail+ffmpeg:-c:a copy" \
            -o "%(title)s - %(uploader)s.%(ext)s" \
            "$URL"
        ;;
    *)
        # Default / Fallback (Audio without thumbnail crop)
        yt-dlp -f 251 -x --audio-format mp3 \
            --extractor-args "youtube:player-client=web_embedded,tv" \
            --embed-thumbnail --embed-metadata \
            --ppa "EmbedThumbnail+ffmpeg:-c:a copy" \
            -o "%(title)s - %(uploader)s" \
            "$URL"
        ;;
esac
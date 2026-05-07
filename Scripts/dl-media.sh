#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title dl-media-pro
# @raycast.mode fullOutput
# @raycast.icon 📥
# @raycast.argument1 { "type": "text", "placeholder": "貼上網址", "secure": false }
# @raycast.argument2 { "type": "dropdown", "placeholder": "類型", "data": [{"title": "🎧 音訊", "value": "1"}, {"title": "🎥 影片", "value": "3"}] }

# === v5.3.2 互動擴充版 (精準淨化字幕版) ===
# 1. 精準過濾：只刪除 <c> 標籤，完美保留逐字時間軸 (<00:xx:xx>)。
# 2. 雙重存檔：同時保留原始 .vtt 供後續專業軟體轉換使用。
# ========================

set -euo pipefail

DOWNLOADS_DIR="${HOME}/Downloads"
COOKIES_FILE="/opt/homebrew/yt-dlp_cookie_bilibili.txt"

# === 1. 變數初始化與互動邏輯 ===
INPUT_URL="${1:-}"
MEDIA_TYPE="${2:-}"
CUSTOM_FORMAT=""

if [[ -z "$INPUT_URL" ]]; then
  echo "📥 全能下載器 v5.3.2 (精準淨化版)"
  read -r -p "🔗 請貼上網址: " INPUT_URL
  [[ -z "$INPUT_URL" ]] && exit 1
  
  echo "🎯 下載類型：[1] 🎧音訊 [2] 🔕無聲 [3] 🎥有聲"
  read -r -p "選擇 (預設 1): " MEDIA_TYPE
  MEDIA_TYPE=${MEDIA_TYPE:-1}
  
  if [[ "$MEDIA_TYPE" == "1" ]]; then
      echo "🎵 選擇格式：[1] M4A (原生無損) [2] MP3 (320k)"
      read -r -p "選擇 (預設 1): " FMT_CHOICE
      [[ "$FMT_CHOICE" == "2" ]] && CUSTOM_FORMAT="mp3" || CUSTOM_FORMAT="m4a"
  else
      echo "🎞️ 選擇格式：[1] MP4 (高相容) [2] MKV (最高畫質)"
      read -r -p "選擇 (預設 1): " FMT_CHOICE
      [[ "$FMT_CHOICE" == "2" ]] && CUSTOM_FORMAT="mkv" || CUSTOM_FORMAT="mp4"
  fi
else
  MEDIA_TYPE=${MEDIA_TYPE:-1}
  [[ "$MEDIA_TYPE" == "1" ]] && CUSTOM_FORMAT="m4a" || CUSTOM_FORMAT="mp4"
fi

TARGET_EXT="$CUSTOM_FORMAT"

# === 2. 核心參數配置 ===
COOKIE_ARGS=(--cookies-from-browser safari)
[[ "$INPUT_URL" == *"bilibili.com"* && -f "$COOKIES_FILE" ]] && COOKIE_ARGS=(--cookies "$COOKIES_FILE")

DL_ARGS=(
  --ignore-errors --no-overwrites --embed-thumbnail --embed-metadata 
  --embed-chapters --convert-thumbnails jpg --restrict-filenames
  --sponsorblock-remove "sponsor,intro,outro"
)

echo "🔍 正在分析資訊..."
INFO_JSON=$(yt-dlp "${COOKIE_ARGS[@]}" --dump-json --no-warnings --playlist-items 1 "$INPUT_URL" 2>/dev/null || echo "{}")

HAS_SUBS=$(echo "$INFO_JSON" | jq -r '.subtitles + .automatic_captions | if . != null and length > 0 then "true" else "false" end')
if [[ "$HAS_SUBS" == "true" ]]; then
    [[ "$MEDIA_TYPE" == "1" ]] && DL_ARGS+=(--write-subs --write-auto-subs) || DL_ARGS+=(--embed-subs --write-subs --write-auto-subs)
    DL_ARGS+=(--sub-langs "zh-Hant,zh-TW,zh-HK,zh-Hans,zh,en,ja,danmaku")
fi

# === 3. 格式與品質精準掛載 ===
if [[ "$MEDIA_TYPE" == "1" ]]; then
    if [[ "$CUSTOM_FORMAT" == "mp3" ]]; then
        DL_ARGS+=(--extract-audio --audio-format "mp3" --audio-quality "320k" -f "bestaudio")
    else
        DL_ARGS+=(--extract-audio --audio-format "m4a" -f "bestaudio[ext=m4a]/bestaudio")
    fi
else
    if [[ "$CUSTOM_FORMAT" == "mkv" ]]; then
        DL_ARGS+=(--merge-output-format "mkv" -f "bv*+ba/best")
    else
        DL_ARGS+=(--merge-output-format "mp4" -f "bv*[vcodec^=avc]+ba[ext=m4a]/best[ext=mp4]/best")
    fi
fi

# === 4. 處理清單邏輯 ===
PLAYLIST_URLS=($(yt-dlp "${COOKIE_ARGS[@]}" --flat-playlist --print webpage_url "$INPUT_URL" 2>/dev/null || echo "$INPUT_URL"))
TOTAL=${#PLAYLIST_URLS[@]}
TARGET_DIR="$DOWNLOADS_DIR"

if [[ $TOTAL -gt 1 ]]; then
    TITLE=$(yt-dlp "${COOKIE_ARGS[@]}" --flat-playlist --print playlist_title --playlist-items 1 "$INPUT_URL" 2>/dev/null | head -n 1 | sed 's/[\/:*?"<>|]/_/g' || echo "Playlist")
    TARGET_DIR="${DOWNLOADS_DIR}/${TITLE}"; mkdir -p "$TARGET_DIR"
fi

# === 5. 執行下載環節 ===
SUCCESS=0; FAIL=0
for (( i=0; i<TOTAL; i++ )); do
    URL="${PLAYLIST_URLS[$i]}"; TS=$(date +"%Y%m%d_%H%M%S")
    echo "🎬 下載中 ($((i+1))/$TOTAL)..."
    
    RAW_TITLE=$(yt-dlp --get-title "$URL" 2>/dev/null | tr -d '\n\r' | sed 's/[\/:*?"<>|]/_/g' || echo "Video")
    FNAME=$([[ $TOTAL -gt 1 ]] && printf "%02d-%s_%s.%s" $((i+1)) "$RAW_TITLE" "$TS" "$TARGET_EXT" || echo "${RAW_TITLE}_${TS}.${TARGET_EXT}")
    
    TMP_BASE="${TARGET_DIR}/tmp_$TS"
    if yt-dlp "${COOKIE_ARGS[@]}" "${DL_ARGS[@]}" -o "${TMP_BASE}.%(ext)s" "$URL"; then
        DOWNLOADED=$(find "$TARGET_DIR" -name "tmp_$TS.*" ! -name "*.vtt" ! -name "*.srt" ! -name "*.xml" ! -name "*.ass" | head -n 1)
        
        if [[ -f "${TMP_BASE}.danmaku.xml" ]] && command -v danmaku2ass >/dev/null; then
            danmaku2ass "${TMP_BASE}.danmaku.xml" -o "${TMP_BASE}.ass" >/dev/null 2>&1
            ffmpeg -i "$DOWNLOADED" -i "${TMP_BASE}.ass" -map 0 -map 1 -c copy -c:s mov_text "${TARGET_DIR}/$FNAME" -y -hide_banner -loglevel error
            rm -f "$DOWNLOADED"
        else
            mv "$DOWNLOADED" "${TARGET_DIR}/$FNAME"
        fi
        
        # === 修改重點：精準淨化與雙重存檔 ===
        if [[ "$MEDIA_TYPE" == "1" ]]; then
            for sub in "${TMP_BASE}"*.{vtt,srt,lrc}; do
                if [[ -f "$sub" ]]; then
                    # 1. 保存原汁原味的原始檔 (供專業轉換軟體使用)
                    ORIGINAL_SUB="${TARGET_DIR}/${FNAME%.*}.${sub##*.}"
                    mv "$sub" "$ORIGINAL_SUB"
                    
                    # 2. 產生一份移除 <c> 標籤但保留時間軸的乾淨版 (供人類閱讀或簡單播放器使用)
                    CLEAN_SUB="${TARGET_DIR}/${FNAME%.*}_clean.${sub##*.}"
                    sed -E 's/<\/?c[^>]*>//g' "$ORIGINAL_SUB" > "$CLEAN_SUB"
                fi
            done
        fi
        
        rm -f "${TMP_BASE}"* 2>/dev/null || true
        ((SUCCESS++))
        echo "✅ 完成: $FNAME"
    else
        ((FAIL++))
    fi
done

echo "🎉 任務結束！儲存位置：$TARGET_DIR"
[[ $SUCCESS -gt 0 ]] && echo "✨ success $SUCCESS"
[[ $FAIL -gt 0 ]] && echo "⚠️ failed $FAIL"
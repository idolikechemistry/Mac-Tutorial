#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title dl-mp4
# @raycast.mode fullOutput
# @raycast.icon 🎥
# @raycast.description 下載影片 (v4.0.7)
# @raycast.argument1 { "type": "text", "placeholder": "貼上網址", "secure": false }
# @raycast.argument2 { "type": "dropdown", "placeholder": "目標格式", "data": [{"title": "高相容優先 (MP4)", "value": "mp4"}, {"title": "最高畫質 (MKV)", "value": "mkv"}] }
# @raycast.argument3 { "type": "dropdown", "placeholder": "字幕與彈幕", "data": [{"title": "自動下載 (優先繁中+彈幕)", "value": "auto"}, {"title": "略過字幕", "value": "none"}] }

# === v4.0.7 Core Updates ===
# 1. 命名規範：嚴格執行「單檔：標題_時間戳」與「清單：序號-標題_時間戳」格式。
# 2. 封裝修正：全面採用 yt-dlp 原生嵌入，確保 Finder 縮圖與 IINA 字幕 100% 可見。
# 3. 雙棲支援：相容 Raycast UI 與 終端機 (Terminal) 互動模式。
# ==============================

set -euo pipefail

# === 1. 初始化與雙棲邏輯 ===
INPUT_URL="${1:-}"
PICK_GOAL="${2:-mp4}"
SUB_STRATEGY="${3:-auto}"

if [[ -z "$INPUT_URL" ]]; then
  echo "🎥 歡迎使用 v4.0.7 命名修正版"
  read -r -p "🔗 請貼上網址: " INPUT_URL
  [[ -z "$INPUT_URL" ]] && exit 1
fi

DOWNLOADS_DIR="${HOME}/Downloads"
COOKIES_FILE="/opt/homebrew/yt-dlp_cookie_bilibili.txt"
TEMP_FILES=()

cleanup() {
  for f in "${TEMP_FILES[@]+"${TEMP_FILES[@]}"}"; do [[ -f "$f" ]] && rm -f "$f"; done
}
trap cleanup EXIT

# === 2. 驗證與路徑分析 ===
echo "🔎 正在分析網址..."
COOKIE_ARGS=(--cookies-from-browser safari)
[[ "$INPUT_URL" == *"bilibili.com"* ]] && [[ -f "$COOKIES_FILE" ]] && COOKIE_ARGS=(--cookies "$COOKIES_FILE")

# 獲取清單
PLAYLIST_URLS=()
while IFS= read -r line; do [[ -n "$line" ]] && PLAYLIST_URLS+=("$line"); done < <(yt-dlp "${COOKIE_ARGS[@]}" --flat-playlist --print webpage_url "$INPUT_URL" 2>/dev/null || true)
TOTAL=${#PLAYLIST_URLS[@]}

TARGET_DIR="$DOWNLOADS_DIR"
IS_PLAYLIST=false
if [[ $TOTAL -gt 1 ]]; then
  IS_PLAYLIST=true
  TITLE=$(yt-dlp "${COOKIE_ARGS[@]}" --flat-playlist --dump-single-json "$INPUT_URL" 2>/dev/null | jq -r '.title // "Playlist"' | sed 's/[\/:*?"<>|]/_/g')
  TARGET_DIR="${DOWNLOADS_DIR}/${TITLE}"; mkdir -p "$TARGET_DIR"
  echo "📚 建立清單資料夾: $TITLE"
fi

# === 3. 下載偏好設定 ===
COMMON_ARGS=(
  --embed-thumbnail
  --embed-metadata
  --embed-chapters
  --embed-subs
  --convert-thumbnails jpg
  --sub-langs "zh-Hant,zh-TW,zh-HK,zh-Hans,zh,en,ja"
)
[[ "$SUB_STRATEGY" == "auto" ]] && COMMON_ARGS+=( --write-subs --write-auto-subs )

# === 4. 迴圈處理 ===
for (( idx=0; idx<TOTAL; idx++ )); do
  VIDEO_URL="${PLAYLIST_URLS[$idx]}"
  # 僅用於暫存檔名，不進入最終成品名
  TS="$(date +"%Y%m%d_%H%M%S")"
  TEMP_ID="TEMP_${TS}_$((RANDOM % 99))"
  
  echo "================================================="
  echo "🎬 處理中 ($((idx+1))/$TOTAL)..."
  
  # 預先抓取乾淨的標題
  RAW_TITLE=$(yt-dlp "${COOKIE_ARGS[@]}" --get-title "$VIDEO_URL" 2>/dev/null | tr -d '\n\r' | sed 's/[\/:*?"<>|]/_/g')
  
  # 建立最終檔名
  if [[ "$IS_PLAYLIST" == true ]]; then
    PREFIX=$(printf "%02d-" $((idx+1)))
    FINAL_NAME="${PREFIX}${RAW_TITLE}_${TS}.${PICK_GOAL}"
  else
    FINAL_NAME="${RAW_TITLE}_${TS}.${PICK_GOAL}"
  fi
  
  FINAL_PATH="${TARGET_DIR}/${FINAL_NAME}"
  TEMP_FILE_BASE="${TARGET_DIR}/${TEMP_ID}"

  echo "▶️ 下載資源: $RAW_TITLE"
  yt-dlp "${COOKIE_ARGS[@]}" "${COMMON_ARGS[@]}" \
    -f "bv*[vcodec^=avc]+ba[ext=m4a]/best[ext=mp4]/best" \
    --merge-output-format "$PICK_GOAL" \
    --write-subs --sub-langs "danmaku" \
    -o "${TEMP_FILE_BASE}.%(ext)s" "$VIDEO_URL"

  # 尋找 yt-dlp 合併後的檔案
  MAIN_FILE=""
  for ext in mp4 mkv webm; do [[ -f "${TEMP_FILE_BASE}.${ext}" ]] && MAIN_FILE="${TEMP_FILE_BASE}.${ext}" && break; done
  [[ -z "$MAIN_FILE" ]] && { echo "❌ 下載失敗"; continue; }

  # --- 處理彈幕補強 ---
  XML_DANMAKU="${TEMP_FILE_BASE}.danmaku.xml"
  if [[ -f "$XML_DANMAKU" ]] && command -v danmaku2ass >/dev/null; then
    echo "📝 嵌入彈幕軌道..."
    ASS_PATH="${TEMP_FILE_BASE}.ass"
    danmaku2ass --size "1920x1080" --fontsize 36 --alpha 0.7 "$XML_DANMAKU" -o "$ASS_PATH" >/dev/null 2>&1
    
    FINAL_TEMP="${TEMP_FILE_BASE}_final.${PICK_GOAL}"
    ffmpeg -hide_banner -loglevel error -i "$MAIN_FILE" -i "$ASS_PATH" \
      -map 0 -map 1 -c copy -c:s:1 mov_text \
      -metadata:s:s:1 title="Danmaku" -disposition:s:s:1 0 "$FINAL_TEMP"
    
    mv "$FINAL_TEMP" "$FINAL_PATH"
    rm -f "$MAIN_FILE"
  else
    # 沒有彈幕，直接重新命名
    mv "$MAIN_FILE" "$FINAL_PATH"
  fi

  # 清理該影片的剩餘殘留（如 xml）
  rm -f "${TEMP_FILE_BASE}"* 2>/dev/null || true
  echo "✅ 儲存成功：$FINAL_NAME"
done

echo "---"
echo "🎉 任務全部完成！儲存位置：$TARGET_DIR"
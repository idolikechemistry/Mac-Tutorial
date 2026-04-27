#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title YouTube / BiliBili Video Downloader
# @raycast.mode fullOutput
# @raycast.icon 🎥
# @raycast.description 下載影片 (v4.0.3)，支援單支影片與播放清單
# @raycast.argument1 { "type": "text", "placeholder": "貼上影片或播放清單網址", "secure": false }
# @raycast.argument2 { "type": "dropdown", "placeholder": "目標格式", "data": [{"title": "高相容優先 (MP4)", "value": "mp4"}, {"title": "最高畫質 (MKV)", "value": "mkv"}] }
# @raycast.argument3 { "type": "dropdown", "placeholder": "字幕與彈幕", "data": [{"title": "自動下載 (優先繁中+彈幕)", "value": "auto"}, {"title": "略過字幕", "value": "none"}] }

# === v4.0.3 Core Updates ===
# 1. 完整整合 Raycast 原生 UI 引數，完美兼容背景靜默執行。
# 2. 移除彈幕強制字體，依賴播放器與系統預設機制，提升跨平台相容性與穩定度。
# 3. 字幕語言優先順序強化 (zh-Hant > zh-TW > zh-HK)。
# 4. 播放清單自動採用「01-標題_時間戳.mp4」格式並建立專屬資料夾。
# ==============================

set -euo pipefail

# === 1. 初始化變數與環境 ===
INPUT_URL="$1"
PICK_GOAL="$2"
SUB_STRATEGY="$3"

DOWNLOADS_DIR="${HOME}/Downloads"
COOKIES_FILE="/opt/homebrew/yt-dlp_cookie_bilibili.txt"
TEMP_FILES=()

# 安全清理機制 (Global Fallback)
cleanup() {
  for f in "${TEMP_FILES[@]+"${TEMP_FILES[@]}"}"; do
    [[ -f "$f" ]] && rm -f "$f"
  done
}
trap cleanup EXIT

# 檢查核心依賴
for cmd in jq ffmpeg ffprobe yt-dlp; do
  if ! command -v "$cmd" >/dev/null; then
    echo "❌ 錯誤：未找到 '$cmd'。請透過 Homebrew 安裝。"
    exit 1
  fi
done

supports_browser() { yt-dlp -h 2>/dev/null | grep -qiE "Supported browsers.*\b$1\b"; }
sanitize_ffmpeg_meta() { tr -d '\n\r' | sed 's/\\/\\\\/g; s/=/\\=/g; s/;/\\;/g; s/#/\\#/g'; }

# === 2. 網站識別與登入狀態驗證 ===
SITE_ARGS=()
IS_BILIBILI=false
[[ "$(echo "$INPUT_URL" | awk -F/ '{print $3}' | tr '[:upper:]' '[:lower:]')" == *"bilibili.com"* ]] && { SITE_ARGS+=( --referer "https://www.bilibili.com" ); IS_BILIBILI=true; }

echo "🔎 驗證登入狀態 (Auth Check)..."
COOKIE_ARGS=()
if [[ "$IS_BILIBILI" == true ]] && [[ -f "$COOKIES_FILE" ]]; then
  COOKIE_ARGS=(--cookies "$COOKIES_FILE")
elif [[ "$IS_BILIBILI" == false ]]; then
  if ! yt-dlp --playlist-items 1 --simulate "$INPUT_URL" >/dev/null 2>&1; then
    for browser in safari chrome chromium arc; do
      if supports_browser "$browser"; then
        if yt-dlp --cookies-from-browser "$browser" --playlist-items 1 --simulate "$INPUT_URL" >/dev/null 2>&1; then
          COOKIE_ARGS=(--cookies-from-browser "$browser"); break
        fi
      fi
    done
  fi
fi

# === 3. 提取清單與動態目錄設定 ===
echo "🔎 分析連結結構..."
PLAYLIST_URLS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && PLAYLIST_URLS+=("$line")
done < <(yt-dlp ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} --flat-playlist --print webpage_url "$INPUT_URL" 2>/dev/null || true)

TOTAL_VIDEOS=${#PLAYLIST_URLS[@]}
if [[ $TOTAL_VIDEOS -eq 0 ]]; then
  echo "❌ 無法提取影片，可能是連結失效或需要付費會員權限。"
  exit 1
fi

TARGET_DIR="$DOWNLOADS_DIR"
if [[ $TOTAL_VIDEOS -gt 1 ]]; then
  PLAYLIST_TITLE=$(yt-dlp --flat-playlist --dump-single-json "$INPUT_URL" 2>/dev/null | jq -r '.title // .channel // "Playlist"' | sed 's/[\/:*?"<>|]/_/g')
  TARGET_DIR="${DOWNLOADS_DIR}/${PLAYLIST_TITLE}"
  mkdir -p "$TARGET_DIR"
  echo "📚 偵測為播放清單，已建立專屬目錄：$PLAYLIST_TITLE"
fi

# === 4. 全域下載偏好設定 ===
if [[ "$PICK_GOAL" == "mp4" ]]; then
  FORMAT_ARGS=( -f 'bv[vcodec~="^((avc)|(hvc)|(hev))"]+ba[ext=m4a] / bv+ba' )
  MERGE_FORMAT="mp4/mkv"; FINAL_TARGET_EXT="mp4"; FORCE_MP4_REMUX=true
else
  FORMAT_ARGS=( -f 'bv+ba / bv[vcodec~="^((avc)|(hvc)|(hev))"]+ba[ext=m4a]' )
  MERGE_FORMAT="mkv/mp4"; FINAL_TARGET_EXT="mkv"; FORCE_MP4_REMUX=false
fi

SUB_ARGS=()
if [[ "$SUB_STRATEGY" == "auto" ]]; then
  SUB_ARGS=( --write-subs --convert-subs srt --sub-langs "zh-Hant,zh-TW,zh-HK,zh-Hans,zh,en,ja,danmaku" )
fi

# ==========================================
# === 5. 影片處理核心迴圈 (The Outer Loop) ===
# ==========================================
for (( idx=0; idx<TOTAL_VIDEOS; idx++ )); do
  VIDEO_URL="${PLAYLIST_URLS[$idx]}"
  UNIQUE_ID="$(date +"%Y%m%d_%H%M%S")_$(($RANDOM % 1000))"
  
  echo "================================================="
  echo "🎬 正在處理 ($((idx+1))/$TOTAL_VIDEOS)..."
  
  INFO_JSON_RAW="$(yt-dlp ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} --skip-download --dump-single-json "$VIDEO_URL" 2>/dev/null || true)"
  if [[ -z "$INFO_JSON_RAW" ]]; then
    echo "⚠️ 提取該影片資訊失敗，略過此項。"
    continue
  fi
  
  INFO_JSON_PATH="${TARGET_DIR}/info_${UNIQUE_ID}.info.json"
  TEMP_FILES+=("$INFO_JSON_PATH")
  printf "%s" "$INFO_JSON_RAW" > "$INFO_JSON_PATH"

  WANT_CHAPTERS=false
  if jq -e '.chapters and (.chapters|length>0)' "$INFO_JSON_PATH" >/dev/null 2>&1; then
    WANT_CHAPTERS=true
  fi

  # 檔名與路徑規劃 (支援播放清單自動序號前綴)
  RAW_TITLE=$(jq -r '.title // "Video"' "$INFO_JSON_PATH" | tr -d '\n\r' | sed 's/[\/:*?"<>|]/_/g')
  PREFIX=""
  [[ $TOTAL_VIDEOS -gt 1 ]] && PREFIX="$(printf "%02d" $((idx+1)))-"
  
  FINAL_RENAMED_PATH="${TARGET_DIR}/${PREFIX}${RAW_TITLE}_${UNIQUE_ID}.${FINAL_TARGET_EXT}"
  TEMP_OUTPUT_TMPL="${TARGET_DIR}/${UNIQUE_ID}_TEMP.%(ext)s"
  
  COMMON_ARGS=( --merge-output-format "$MERGE_FORMAT" --write-thumbnail --output "$TEMP_OUTPUT_TMPL" )
  [[ "$FORCE_MP4_REMUX" == true ]] && COMMON_ARGS+=( --remux-video mp4 )

  echo "▶️ 下載中: ${PREFIX}${RAW_TITLE}"
  if ! yt-dlp ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} ${FORMAT_ARGS[@]+"${FORMAT_ARGS[@]}"} ${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"} ${SUB_ARGS[@]+"${SUB_ARGS[@]}"} "$VIDEO_URL"; then
     echo "❌ 該影片下載失敗，跳至下一個..."
     continue
  fi

  # 尋找下載好的主檔與封面
  FINAL_OUTPUT=""
  for ext in mp4 mkv webm; do
    if [[ -f "${TARGET_DIR}/${UNIQUE_ID}_TEMP.${ext}" ]]; then
      FINAL_OUTPUT="${TARGET_DIR}/${UNIQUE_ID}_TEMP.${ext}"
      break
    fi
  done
  [[ -z "$FINAL_OUTPUT" ]] && { echo "⚠️ 找不到目標影片檔，略過..."; continue; }

  THUMBNAIL_PATH=""
  for ext in webp jpg png; do
    if [[ -f "${TARGET_DIR}/${UNIQUE_ID}_TEMP.${ext}" ]]; then
      THUMBNAIL_PATH="${TARGET_DIR}/${UNIQUE_ID}_TEMP.${ext}"
      TEMP_FILES+=("$THUMBNAIL_PATH")
      break
    fi
  done

  # 彈幕 (Danmaku) 轉換 (移除指定字體，採用預設排版)
  ASS_PATH=""
  if command -v danmaku2ass >/dev/null && [[ -f "${TARGET_DIR}/${UNIQUE_ID}_TEMP.danmaku.xml" ]]; then
    XML_PATH="${TARGET_DIR}/${UNIQUE_ID}_TEMP.danmaku.xml"
    ASS_PATH="${XML_PATH%.xml}.ass"
    TEMP_FILES+=("$ASS_PATH" "$XML_PATH")
    
    VIDEO_RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$FINAL_OUTPUT" 2>/dev/null || echo "1920x1080")
    [[ "$VIDEO_RES" != *[0-9]*x[0-9]* ]] && VIDEO_RES="1920x1080"
    
    echo "📝 轉換彈幕為字幕格式 (動態字體)..."
    danmaku2ass --size "${VIDEO_RES}" --fontsize 36 --alpha 0.7 "$XML_PATH" -o "$ASS_PATH" >/dev/null 2>&1
  fi

  declare -a SRT_FILES=()
  while IFS= read -r -d $'\0'; do SRT_FILES+=("$REPLY"); done < <(find "$TARGET_DIR" -maxdepth 1 -type f -name "*_${UNIQUE_ID}_TEMP.*.srt" -print0)

  # Ffmpeg 合併與中繼資料寫入
  echo "🎬 Ffmpeg 封裝處理中..."
  METADATA_TXT="${TARGET_DIR}/metadata_${UNIQUE_ID}.txt"
  FINAL_OUTPUT_PATH_TEMP="${TARGET_DIR}/${UNIQUE_ID}_META_TEMP.${FINAL_TARGET_EXT}"
  TEMP_FILES+=("$METADATA_TXT" "$FINAL_OUTPUT_PATH_TEMP")

  echo ";FFMETADATA1" > "$METADATA_TXT"
  echo "title=$(jq -r '.title // "N/A"' "$INFO_JSON_PATH" | sanitize_ffmpeg_meta)" >> "$METADATA_TXT"
  echo "artist=$(jq -r '.uploader // "N/A"' "$INFO_JSON_PATH" | sanitize_ffmpeg_meta)" >> "$METADATA_TXT"
  echo "comment=$(jq -r '.webpage_url // "N/A"' "$INFO_JSON_PATH" | sanitize_ffmpeg_meta)" >> "$METADATA_TXT"
  echo "[DESCRIPTION]" >> "$METADATA_TXT"
  jq -r '.description // "N/A"' "$INFO_JSON_PATH" | sed 's/\[CHAPTER\]/\[_CHAPTER_\]/g' >> "$METADATA_TXT"

  if [[ "$WANT_CHAPTERS" == true ]]; then
    jq -c '.chapters[]' "$INFO_JSON_PATH" | while read -r ch; do
      s="$(jq -r '.start_time' <<<"$ch")"; e="$(jq -r '.end_time' <<<"$ch")"
      t="$(jq -r '.title' <<<"$ch" | tr '\n\r' ' ' | sed 's/[]\[\"]//g' | sanitize_ffmpeg_meta)"
      printf "[CHAPTER]\nTIMEBASE=1/1000\nSTART=%.0f\nEND=%.0f\ntitle=%s\n" "$(awk "BEGIN{print $s * 1000}")" "$(awk "BEGIN{print $e * 1000}")" "$t" >> "$METADATA_TXT"
    done
  fi

  FFMPEG_INPUTS=( -i "$FINAL_OUTPUT" -i "$METADATA_TXT" )
  FFMPEG_MAPS=( -map 0 )
  FFMPEG_CODECS=( -c copy )
  FFMPEG_META=( -map_metadata 1 )
  SUB_IDX=0

  if [[ -n "$THUMBNAIL_PATH" ]]; then
    FFMPEG_INPUTS+=( -i "$THUMBNAIL_PATH" ); FFMPEG_MAPS+=( -map 2 )
    FFMPEG_CODECS+=( -c:v:1 mjpeg -disposition:v:1 attached_pic )
  fi

  if [[ ${#SRT_FILES[@]} -gt 0 ]]; then 
    SUB_CODEC="mov_text"; [[ "$FINAL_TARGET_EXT" == "mkv" ]] && SUB_CODEC="srt"
    for srt_file in "${SRT_FILES[@]}"; do
      FFMPEG_INPUTS+=( -i "$srt_file" ); FFMPEG_MAPS+=( -map $((${#FFMPEG_INPUTS[@]}-1)) )
      FFMPEG_CODECS+=( -c:s:${SUB_IDX} "$SUB_CODEC" )
      lang_full=$(basename "$srt_file" .srt | rev | cut -d. -f1 | rev)
      
      case "$lang_full" in 
        zh-Hant|zh-TW|zh-HK) lang_code="zht";; 
        zh-Hans|zh-CN|zh) lang_code="chi";; 
        en*) lang_code="eng";; 
        ja*) lang_code="jpn";; 
        *) lang_code="${lang_full:0:3}";; 
      esac
      
      FFMPEG_CODECS+=( -metadata:s:s:${SUB_IDX} "language=${lang_code}" )
      SUB_IDX=$((SUB_IDX + 1))
    done
  fi

  if [[ -n "$ASS_PATH" ]]; then
    ASS_CODEC="mov_text"; [[ "$FINAL_TARGET_EXT" == "mkv" ]] && ASS_CODEC="ass"
    FFMPEG_INPUTS+=( -i "$ASS_PATH" ); FFMPEG_MAPS+=( -map $((${#FFMPEG_INPUTS[@]}-1)) )
    FFMPEG_CODECS+=( -c:s:${SUB_IDX} "$ASS_CODEC" -metadata:s:s:${SUB_IDX} "language=zht" -metadata:s:s:${SUB_IDX} "title=Danmaku" )
  fi

  ffmpeg -hide_banner -loglevel error "${FFMPEG_INPUTS[@]}" "${FFMPEG_MAPS[@]}" "${FFMPEG_CODECS[@]}" "${FFMPEG_META[@]}" "$FINAL_OUTPUT_PATH_TEMP"
  ffmpeg -hide_banner -loglevel error -i "$FINAL_OUTPUT_PATH_TEMP" -c copy -movflags +faststart "$FINAL_RENAMED_PATH"

  # 單一影片暫存清理
  for f in "${TEMP_FILES[@]+"${TEMP_FILES[@]}"}"; do
    [[ -f "$f" ]] && rm -f "$f"
  done
  TEMP_FILES=()
  rm -f "${TARGET_DIR}"/*_"${UNIQUE_ID}"_TEMP.*.srt 2>/dev/null || true
  rm -f "${TARGET_DIR}"/*_"${UNIQUE_ID}"_TEMP.danmaku.xml 2>/dev/null || true
  rm -f "${TARGET_DIR}/${UNIQUE_ID}_TEMP".* 2>/dev/null || true

  echo "✅ 儲存成功：$(basename "$FINAL_RENAMED_PATH")"
  sleep 1
done

echo "---"
echo "🎉 處理完成！所有檔案已儲存至：${TARGET_DIR}"
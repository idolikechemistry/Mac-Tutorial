#!/bin/bash

# @raycast.title YouTube Audio Downloader
# @raycast.description 下載 YouTube 音訊為 mp3 或 m4a，先偵測 chapters[]，再由使用者選擇是否嵌入（單支影片+m4a）
# @raycast.mode compact

# Ver 20250912

set -euo pipefail

# --- 檢查必要工具 ---
for cmd in yt-dlp ffmpeg jq; do
  command -v "$cmd" >/dev/null || { echo "❌ 未找到 $cmd"; exit 1; }
done

DOWNLOADS_DIR="${HOME}/Downloads"
CURRENT_DATETIME="$(date +"%Y%m%d_%H%M%S")"

read -p "請輸入影片 URL: " VIDEO_URL
read -p "請選擇輸出格式 , mp3 (1) / m4a (2) : " FORMAT_CHOICE

if [[ "$FORMAT_CHOICE" == "1" ]]; then
  AUDIO_FORMAT="mp3"
  AUDIO_QUALITY_ARGS=(--audio-quality "320k")
elif [[ "$FORMAT_CHOICE" == "2" ]]; then
  AUDIO_FORMAT="m4a"
  AUDIO_QUALITY_ARGS=()
else
  echo "無效選項，請輸入 1 或 2。"; exit 1
fi

# --- 判斷是否為播放清單 ---
IS_PLAYLIST=false
if yt-dlp --flat-playlist --dump-single-json "$VIDEO_URL" 2>/dev/null | jq -e '.entries | length > 1' >/dev/null; then
  IS_PLAYLIST=true
fi

# --- 共同下載參數 ---
COMMON_OPTIONS=(
  --ignore-errors
  --no-overwrites
  --embed-thumbnail
  --embed-metadata
  --add-metadata
  --convert-thumbnails jpg
  --restrict-filenames
)

# --- 依格式指定最適音訊 ---
if [[ "$AUDIO_FORMAT" == "m4a" ]]; then
  # 優先原生 m4a (140)，沒有再轉
  FORMAT_SELECTOR='bestaudio[ext=m4a]/140/bestaudio'
  COMMON_OPTIONS+=(--extract-audio --audio-format m4a)
else
  FORMAT_SELECTOR='bestaudio'
  COMMON_OPTIONS+=(--extract-audio --audio-format mp3 "${AUDIO_QUALITY_ARGS[@]}")
fi

# === 先偵測 chapters[]，並詢問是否嵌入（僅單支影片時有意義） ===
WANT_CHAPTERS=false
CHAPTERS_AVAILABLE=false
CHAPTER_COUNT=0
INFO_JSON=""

detect_chapters() {
  # 只在「非播放清單」時檢查
  if [[ "$IS_PLAYLIST" == true ]]; then
    return 0
  fi
  # 直接 dump 單支影片 JSON（不下載媒體）
  local json
  json="$(yt-dlp --skip-download --dump-single-json "$VIDEO_URL" 2>/dev/null || true)"
  if [[ -n "$json" ]] && echo "$json" | jq -e '.chapters and (.chapters|length>0)' >/dev/null 2>&1; then
    CHAPTERS_AVAILABLE=true
    CHAPTER_COUNT="$(echo "$json" | jq '.chapters|length')"
    # 暫存供後續嵌入使用
    INFO_JSON="${DOWNLOADS_DIR}/info_${CURRENT_DATETIME}.info.json"
    printf "%s" "$json" > "$INFO_JSON"
  fi
}

prompt_for_chapters() {
  if [[ "$IS_PLAYLIST" == true ]]; then
    echo "ℹ️ 偵測為播放清單；播放清單不支援整合章節到單一檔案。"
    return 0
  fi
  if [[ "$AUDIO_FORMAT" != "m4a" ]]; then
    # 維持既有規則：只有 m4a 才做章節嵌入
    if [[ "$CHAPTERS_AVAILABLE" == true ]]; then
      echo "ℹ️ 偵測到 ${CHAPTER_COUNT} 個章節，但目前格式為 mp3；將略過章節嵌入（僅 m4a 支援）。"
    else
      echo "ℹ️ 未偵測到章節。"
    fi
    return 0
  fi

  if [[ "$CHAPTERS_AVAILABLE" == true ]]; then
    read -r -p "🔎 偵測到 ${CHAPTER_COUNT} 個章節，是否要嵌入到音檔？(y/N) " ans
    case "$ans" in
      y|Y) WANT_CHAPTERS=true ;;
      *)   WANT_CHAPTERS=false ;;
    esac
  else
    echo "ℹ️ 未偵測到章節。"
  fi
}

detect_chapters
prompt_for_chapters

# --- 單支影片下載（標題-時間） ---
download_single_video () {
  RAW_TITLE="$(yt-dlp --get-title "$VIDEO_URL" | tr -d '\n\r')"
  CLEAN_TITLE="$(printf "%s" "$RAW_TITLE" | sed 's/[\/:*?"<>|]/_/g')"
  OUTPUT_PATH="${DOWNLOADS_DIR}/${CLEAN_TITLE}-${CURRENT_DATETIME}.${AUDIO_FORMAT}"

  echo "🎧 正在下載音訊（單支影片）..."
  if ! yt-dlp -f "$FORMAT_SELECTOR" -o "$OUTPUT_PATH" "${COMMON_OPTIONS[@]}" "$VIDEO_URL"; then
    echo "未成功下載，檢查是否需要登入或年齡驗證。"
    if yt-dlp --simulate "$VIDEO_URL" 2>&1 | grep -Eiq "Sign in to confirm your age|private|requires age verification"; then
      echo "正在嘗試使用 Safari 的 Cookies 重新下載..."
      yt-dlp --cookies-from-browser safari -f "$FORMAT_SELECTOR" -o "$OUTPUT_PATH" "${COMMON_OPTIONS[@]}" "$VIDEO_URL" || exit 1
    else
      echo "未檢測到需要登入的相關問題，請檢查其他錯誤原因。"; exit 1
    fi
  fi
  echo "✅ 下載完成：$(basename "$OUTPUT_PATH")"

  # --- 章節嵌入（僅當 WANT_CHAPTERS=true 且 m4a）---
  if [[ "$WANT_CHAPTERS" == true && "$AUDIO_FORMAT" == "m4a" ]]; then
    echo "📚 正在嵌入章節..."
    # 確保有 INFO_JSON（若之前沒存到，保險再抓一次）
    if [[ -z "${INFO_JSON:-}" || ! -f "$INFO_JSON" ]]; then
      INFO_JSON="${DOWNLOADS_DIR}/info_${CURRENT_DATETIME}.info.json"
      yt-dlp --skip-download --write-info-json -o "${DOWNLOADS_DIR}/info_${CURRENT_DATETIME}.%(ext)s" "$VIDEO_URL" || true
    fi

    if [[ -f "$INFO_JSON" ]] && jq -e '.chapters and (.chapters|length>0)' "$INFO_JSON" >/dev/null 2>&1; then
      CHAPTERS_TXT="${DOWNLOADS_DIR}/chapters_${CURRENT_DATETIME}.txt"
      {
        echo ";FFMETADATA1"
        jq -c '.chapters[]' "$INFO_JSON" | while read -r chapter; do
          start="$(jq -r '.start_time' <<<"$chapter")"
          end="$(jq -r '.end_time' <<<"$chapter")"
          title="$(jq -r '.title' <<<"$chapter" | tr '\n\r' ' ' | sed 's/[]\[\"]//g')"
          printf "[CHAPTER]\nTIMEBASE=1/1\nSTART=%s\nEND=%s\ntitle=%s\n" "${start%.*}" "${end%.*}" "$title"
        done
      } > "$CHAPTERS_TXT"

      TEMP_OUTPUT="${DOWNLOADS_DIR}/temp_chapters_${CURRENT_DATETIME}.m4a"
      ffmpeg -hide_banner -loglevel error -i "$OUTPUT_PATH" -i "$CHAPTERS_TXT" \
        -map_metadata 0 -map_metadata 1 -c copy "$TEMP_OUTPUT"
      mv -f "$TEMP_OUTPUT" "$OUTPUT_PATH"
      rm -f "$CHAPTERS_TXT" "$INFO_JSON"
      echo "✅ 章節已嵌入到：$(basename "$OUTPUT_PATH")"
    else
      echo "ℹ️ 未找到可用章節（略過章節嵌入）"
    fi
  fi
}

# --- 播放清單下載（序號-標題-時間；不含ID，不做章節流程）---
download_playlist () {
  echo "🎧 正在下載音訊（播放清單；逐首下載）..."
  TEMPLATE="${DOWNLOADS_DIR}/%(playlist_title|channel)s/%(playlist_index)02d - %(title)s-%(epoch>%Y%m%d_%H%M%S)s.%(ext)s"

  if ! yt-dlp -f "$FORMAT_SELECTOR" -o "$TEMPLATE" "${COMMON_OPTIONS[@]}" "$VIDEO_URL"; then
    echo "未成功下載，檢查是否需要登入或年齡驗證。"
    if yt-dlp --simulate "$VIDEO_URL" 2>&1 | grep -Eiq "Sign in to confirm your age|private|requires age verification"; then
      echo "正在嘗試使用 Safari 的 Cookies 重新下載（清單）..."
      yt-dlp --cookies-from-browser safari -f "$FORMAT_SELECTOR" -o "$TEMPLATE" "${COMMON_OPTIONS[@]}" "$VIDEO_URL" || exit 1
    else
      echo "未檢測到需要登入的相關問題，請檢查其他錯誤原因。"; exit 1
    fi
  fi

  echo "✅ 播放清單下載完成。"
}

# --- 主流程 ---
if [[ "$IS_PLAYLIST" == true ]]; then
  download_playlist
else
  download_single_video
fi
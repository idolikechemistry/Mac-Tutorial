#!/bin/bash

# === v5.0.4 極簡純粹版 ===
# 1. 移除容易造成混淆的 yt-dlp -F 底層格式列表，專注於輸出成品的選擇。
# 2. 修正 macOS 內建 Bash 3.2 的 bad substitution 報錯問題 (跨平台穩健)。
# 3. 智慧邏輯引導：先選媒體類型 -> 探測章節/字幕 -> 選擇輸出格式與品質。

set -euo pipefail

DOWNLOADS_DIR="${HOME}/Downloads"
COOKIES_FILE="/opt/homebrew/yt-dlp_cookie_bilibili.txt"
TEMP_FILES=()

cleanup() {
  for f in "${TEMP_FILES[@]+"${TEMP_FILES[@]}"}"; do [[ -f "$f" ]] && rm -f "$f"; done
}
trap cleanup EXIT

# 檢查基本依賴
for cmd in yt-dlp ffmpeg jq; do
  if ! command -v "$cmd" >/dev/null; then 
    echo "❌ 錯誤：未安裝 $cmd，請先安裝 (brew install $cmd)。"
    exit 1
  fi
done

echo "=========================================="
echo "  📥 全能影音分析與下載器 (v5.0.4 極簡版)"
echo "=========================================="

# === 1. 提示貼上連結 ===
read -r -p "🔗 請貼上影片或播放清單網址: " INPUT_URL
[[ -z "$INPUT_URL" ]] && { echo "❌ 網址不能為空，腳本終止！"; exit 1; }

COOKIE_ARGS=(--cookies-from-browser safari)
if [[ "$INPUT_URL" == *"bilibili.com"* ]] && [[ -f "$COOKIES_FILE" ]]; then
    COOKIE_ARGS=(--cookies "$COOKIES_FILE")
    echo "🍪 載入 Bilibili 專屬 Cookie..."
fi

# 背景靜默取得 JSON 以供探測
echo "🔍 正在背景分析連結底層資訊..."
INFO_JSON=$(yt-dlp "${COOKIE_ARGS[@]}" --dump-json --no-warnings --playlist-items 1 "$INPUT_URL" 2>/dev/null || echo "{}")

# === 2. 選擇大類型 (影響後續所有邏輯) ===
echo "🎯 請選擇你要下載的媒體類型："
echo "  [1] 🎧 純音訊 (Audio Only)"
echo "  [2] 🔕 無聲影片 (Video Only, 適合當素材)"
echo "  [3] 🎥 有聲影片 (Video + Audio)"
read -r -p "請輸入數字 (1-3，預設 1): " MEDIA_TYPE
[[ -z "$MEDIA_TYPE" ]] && MEDIA_TYPE="1"

DL_ARGS=(
  --ignore-errors
  --no-overwrites
  --embed-thumbnail
  --embed-metadata
  --convert-thumbnails jpg
  --restrict-filenames
)

# === 3. 探測章節並詢問 ===
HAS_CHAPTERS=$(echo "$INFO_JSON" | jq -r 'if .chapters != null and (.chapters | length > 0) then "true" else "false" end')
if [[ "$HAS_CHAPTERS" == "true" ]]; then
    read -r -p "📑 偵測到【章節】資訊！是否嵌入至檔案中？(Y/n, 預設 Y): " ASK_CHAP
    [[ -z "$ASK_CHAP" || "$ASK_CHAP" == "y" || "$ASK_CHAP" == "Y" ]] && DL_ARGS+=( --embed-chapters )
fi

# === 4. 探測字幕/歌詞並根據「類型」分別詢問 ===
HAS_SUBS=$(echo "$INFO_JSON" | jq -r 'if (.subtitles != null and (.subtitles | length > 0)) or (.automatic_captions != null and (.automatic_captions | length > 0)) then "true" else "false" end')

if [[ "$HAS_SUBS" == "true" ]]; then
    if [[ "$MEDIA_TYPE" == "1" ]]; then
        # 純音訊邏輯：只下載不嵌入
        echo "📝 偵測到【字幕】資訊！"
        read -r -p "是否為您下載作為獨立的【歌詞檔】？(純音訊無法直接嵌入) (Y/n, 預設 Y): " ASK_LYRIC
        if [[ -z "$ASK_LYRIC" || "$ASK_LYRIC" == "y" || "$ASK_LYRIC" == "Y" ]]; then
            DL_ARGS+=( --write-subs --write-auto-subs --sub-langs "zh-Hant,zh-TW,zh-HK,zh-Hans,zh,en,ja" )
        fi
    else
        # 影片邏輯：下載且嵌入
        echo "💬 偵測到【字幕/彈幕】資訊！"
        read -r -p "是否下載並【嵌入】至影片中？ (Y/n, 預設 Y): " ASK_SUB
        if [[ -z "$ASK_SUB" || "$ASK_SUB" == "y" || "$ASK_SUB" == "Y" ]]; then
            DL_ARGS+=( --embed-subs --write-subs --write-auto-subs --sub-langs "zh-Hant,zh-TW,zh-HK,zh-Hans,zh,en,ja,danmaku" )
        fi
    fi
fi

# === 5. 選擇格式與品質 ===
echo "------------------------------------------"
TARGET_EXT=""
if [[ "$MEDIA_TYPE" == "1" ]]; then
    echo "🎵 請選擇音訊輸出格式："
    echo "  [1] m4a (預設，原生無損與 Apple 相容)"
    echo "  [2] mp3 (高相容，會進行二次壓縮)"
    read -r -p "請輸入數字 (1-2，預設 1): " AUDIO_FMT
    [[ "$AUDIO_FMT" == "2" ]] && TARGET_EXT="mp3" || TARGET_EXT="m4a"

    echo "🎚️ 請選擇音質規格："
    echo "  [1] 最高規格 (best, 預設)"
    echo "  [2] 320k (高品質)"
    read -r -p "請輸入數字 (1-2，預設 1): " AUDIO_QUAL

    DL_ARGS+=( --extract-audio --audio-format "$TARGET_EXT" --sponsorblock-remove "sponsor,intro,outro" )
    if [[ "$AUDIO_QUAL" == "2" ]]; then
        DL_ARGS+=( -f "bestaudio" --audio-quality "320k" )
    else
        [[ "$TARGET_EXT" == "m4a" ]] && DL_ARGS+=( -f "bestaudio[ext=m4a]/140/bestaudio" ) || DL_ARGS+=( -f "bestaudio" --audio-quality "0" )
    fi
else
    echo "🎞️ 請選擇影片輸出格式："
    echo "  [1] mp4 (高相容，預設)"
    echo "  [2] mkv (最高畫質封裝)"
    read -r -p "請輸入數字 (1-2，預設 1): " VIDEO_FMT
    [[ "$VIDEO_FMT" == "2" ]] && TARGET_EXT="mkv" || TARGET_EXT="mp4"

    echo "📺 請選擇影片畫質："
    echo "  [1] 最高畫質 (best, 預設)"
    echo "  [2] 1080p"
    read -r -p "請輸入數字 (1-2，預設 1): " VIDEO_QUAL

    DL_ARGS+=( --merge-output-format "$TARGET_EXT" )
    
    if [[ "$MEDIA_TYPE" == "2" ]]; then
        if [[ "$VIDEO_QUAL" == "2" ]]; then
            DL_ARGS+=( -f "bv*[height<=1080]" )
        else
            DL_ARGS+=( -f "bv*" )
        fi
    else
        if [[ "$VIDEO_QUAL" == "2" ]]; then
            DL_ARGS+=( -f "bv*[height<=1080]+ba/best" )
        else
            [[ "$TARGET_EXT" == "mp4" ]] && DL_ARGS+=( -f "bv*[vcodec^=avc]+ba[ext=m4a]/best[ext=mp4]/best" ) || DL_ARGS+=( -f "bv*+ba/best" )
        fi
    fi
fi

# === 6. 下載執行環節 (含清單解析) ===
PLAYLIST_URLS=()
while IFS= read -r line; do 
  [[ -n "$line" ]] && PLAYLIST_URLS+=("$line")
done < <(yt-dlp "${COOKIE_ARGS[@]}" --flat-playlist --print webpage_url "$INPUT_URL" 2>/dev/null || true)

TOTAL=${#PLAYLIST_URLS[@]}
[[ $TOTAL -eq 0 ]] && { PLAYLIST_URLS=("$INPUT_URL"); TOTAL=1; }

TARGET_DIR="$DOWNLOADS_DIR"
IS_PLAYLIST=false
if [[ $TOTAL -gt 1 ]]; then
  IS_PLAYLIST=true
  TITLE=$(yt-dlp "${COOKIE_ARGS[@]}" --flat-playlist --dump-single-json "$INPUT_URL" 2>/dev/null | jq -r '.title // "Playlist"' | sed 's/[\/:*?"<>|]/_/g')
  TARGET_DIR="${DOWNLOADS_DIR}/${TITLE}"; mkdir -p "$TARGET_DIR"
  echo "📚 建立清單資料夾: $TITLE (共 $TOTAL 個檔案)"
fi

SUCCESS_COUNT=0
FAIL_COUNT=0

for (( idx=0; idx<TOTAL; idx++ )); do
  VIDEO_URL="${PLAYLIST_URLS[$idx]}"
  TS="$(date +"%Y%m%d_%H%M%S")"
  TEMP_ID="TEMP_${TS}_$((RANDOM % 99))"
  
  echo "================================================="
  echo "▶️ 開始下載 ($((idx+1))/$TOTAL)..."
  
  RAW_TITLE=$(yt-dlp "${COOKIE_ARGS[@]}" --get-title "$VIDEO_URL" 2>/dev/null | tr -d '\n\r' | sed 's/[\/:*?"<>|]/_/g' || echo "Unknown_Title")
  [[ "$IS_PLAYLIST" == true ]] && FINAL_NAME="$(printf "%02d-" $((idx+1)))${RAW_TITLE}_${TS}.${TARGET_EXT}" || FINAL_NAME="${RAW_TITLE}_${TS}.${TARGET_EXT}"
  
  FINAL_PATH="${TARGET_DIR}/${FINAL_NAME}"
  TEMP_FILE_BASE="${TARGET_DIR}/${TEMP_ID}"

  if ! yt-dlp "${COOKIE_ARGS[@]}" "${DL_ARGS[@]}" -o "${TEMP_FILE_BASE}.%(ext)s" "$VIDEO_URL"; then
    echo "⚠️ 下載失敗。"
    ((FAIL_COUNT++)); continue
  fi

  MAIN_FILE=""
  for ext in mp4 mkv webm m4a mp3 ogg flac wav; do 
    [[ -f "${TEMP_FILE_BASE}.${ext}" ]] && MAIN_FILE="${TEMP_FILE_BASE}.${ext}" && break
  done
  
  [[ -z "$MAIN_FILE" ]] && { echo "❌ 找不到實體檔案。"; ((FAIL_COUNT++)); continue; }

  if [[ "$MEDIA_TYPE" != "1" ]]; then
    XML_DANMAKU="${TEMP_FILE_BASE}.danmaku.xml"
    if [[ -f "$XML_DANMAKU" ]] && command -v danmaku2ass >/dev/null; then
      ASS_PATH="${TEMP_FILE_BASE}.ass"
      danmaku2ass --size "1920x1080" --fontsize 36 --alpha 0.7 "$XML_DANMAKU" -o "$ASS_PATH" >/dev/null 2>&1
      FINAL_TEMP="${TEMP_FILE_BASE}_final.${TARGET_EXT}"
      ffmpeg -hide_banner -loglevel error -i "$MAIN_FILE" -i "$ASS_PATH" -map 0 -map 1 -c copy -c:s:1 mov_text -metadata:s:s:1 title="Danmaku" -disposition:s:s:1 0 "$FINAL_TEMP"
      mv "$FINAL_TEMP" "$FINAL_PATH"; rm -f "$MAIN_FILE"
    else
      mv "$MAIN_FILE" "$FINAL_PATH"
    fi
  else
    mv "$MAIN_FILE" "$FINAL_PATH"
  fi

  # 清理其餘不必要的殘留檔 (保留使用者要的獨立歌詞檔 .vtt/.lrc)
  if [[ "$MEDIA_TYPE" == "1" && "$HAS_SUBS" == "true" ]]; then
      for sub in "${TEMP_FILE_BASE}".*; do
          if [[ "$sub" == *".vtt" || "$sub" == *".srt" || "$sub" == *".lrc" ]]; then
              sub_ext="${sub##*.}"
              lang_ext="${sub%.*}"
              lang="${lang_ext##*.}"
              mv "$sub" "${TARGET_DIR}/${FINAL_NAME%.*}.${lang}.${sub_ext}" 2>/dev/null || true
          fi
      done
  fi
  rm -f "${TEMP_FILE_BASE}"* 2>/dev/null || true
  
  ((SUCCESS_COUNT++))
  echo "✅ 已儲存：$FINAL_NAME"
done

echo "=========================================="
echo "🎉 任務結束！儲存位置：$TARGET_DIR"

[[ $SUCCESS_COUNT -gt 0 ]] && echo "✨ success $SUCCESS_COUNT"
[[ $FAIL_COUNT -gt 0 ]] && echo "⚠️ failed $FAIL_COUNT"
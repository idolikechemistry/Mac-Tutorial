#!/bin/bash
# ===
# 20260422_1600:00
# V 4.0.2 (Playlist & Single Hybrid Edition)
# v40.2 Core:
# 1. Added Outer Loop to support both single videos and playlists seamlessly.
# 2. Implemented Global Subtitle Strategy for playlists to avoid repetitive prompts.
# 3. Optimized Cookie detection using fast simulate checks.
# 4. Added per-loop temp cleanup to prevent disk bloat during mass downloads.
# ===
set -euo pipefail

# === 1. Globals & Configuration ===
DOWNLOADS_DIR="${HOME}/Downloads"
COOKIES_FILE="/opt/homebrew/yt-dlp_cookie_bilibili.txt"
TEMP_FILES=() # Array to track temporary files for trap cleanup

# Safe Cleanup Trap (Global Fallback)
cleanup() {
  echo "🧹 Executing global cleanup..."
  for f in "${TEMP_FILES[@]+"${TEMP_FILES[@]}"}"; do
    [[ -f "$f" ]] && rm -f "$f"
  done
}
trap cleanup EXIT

# === 2. Core Dependencies & Helpers ===
check_dependencies() {
  for cmd in jq ffmpeg ffprobe; do
    if ! command -v "$cmd" >/dev/null; then
      echo "❌ Cannot find '$cmd'. Please install via Homebrew (brew install $cmd)."
      exit 1
    fi
  done
}
supports_browser() { yt-dlp -h 2>/dev/null | grep -qiE "Supported browsers.*\b$1\b"; }
contains_lang() { case ",$2," in *,"$1",*) return 0;; *) return 1;; esac; }
sanitize_ffmpeg_meta() { tr -d '\n\r' | sed 's/\\/\\\\/g; s/=/\\=/g; s/;/\\;/g; s/#/\\#/g'; }

# === 3. Initialize URL & Auth ===
check_dependencies
read -p "Please enter video or playlist URL: " INPUT_URL

SITE_ARGS=()
IS_BILIBILI=false
[[ "$(echo "$INPUT_URL" | awk -F/ '{print $3}' | tr '[:upper:]' '[:lower:]')" == *"bilibili.com"* ]] && { SITE_ARGS+=( --referer "https://www.bilibili.com" ); IS_BILIBILI=true; }

echo "🔎 Detecting login status (Auth Check)..."
COOKIE_ARGS=()
if [[ "$IS_BILIBILI" == true ]] && [[ -f "$COOKIES_FILE" ]]; then
  COOKIE_ARGS=(--cookies "$COOKIES_FILE")
elif [[ "$IS_BILIBILI" == false ]]; then
  # Fast auth check without downloading JSON
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
echo "✅ Auth resolved (using ${COOKIE_ARGS[0]:-"no-cookie"})."

# === 4. Extract URLs (Single or Playlist) ===
echo "🔎 Analyzing link structure..."
PLAYLIST_URLS=()
# Mac Bash 3.2 compatible read loop
while IFS= read -r line; do
  [[ -n "$line" ]] && PLAYLIST_URLS+=("$line")
done < <(yt-dlp ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} --flat-playlist --print webpage_url "$INPUT_URL" 2>/dev/null || true)

TOTAL_VIDEOS=${#PLAYLIST_URLS[@]}
if [[ $TOTAL_VIDEOS -eq 0 ]]; then
  echo "❌ Failed to extract any videos. URL may be invalid, private, or require membership."
  exit 1
fi

# === 5. Global Preferences ===
echo "✅ Select download goal:"
echo "  [1] Highest Quality Priority (MKV)"
echo "  [2] Best Compatibility Priority (MP4) [Default]"
read -p "Enter number: " PICK_GOAL

FORMAT_ARGS=( -f 'bv[vcodec~="^((avc)|(hvc)|(hev))"]+ba[ext=m4a] / bv+ba' )
MERGE_FORMAT="mp4/mkv"; FINAL_TARGET_EXT="mp4"; FORCE_MP4_REMUX=true
if [[ "$PICK_GOAL" == "1" ]]; then
  FORMAT_ARGS=( -f 'bv+ba / bv[vcodec~="^((avc)|(hvc)|(hev))"]+ba[ext=m4a]' )
  MERGE_FORMAT="mkv/mp4"; FINAL_TARGET_EXT="mkv"; FORCE_MP4_REMUX=false
fi

# Global Subtitle Strategy for Playlists
SUB_STRATEGY="1"
if [[ $TOTAL_VIDEOS -gt 1 ]]; then
  echo "📚 Playlist detected ($TOTAL_VIDEOS videos)."
  echo "✅ Select global subtitle strategy:"
  echo "  [1] Auto-download best (zh, en, ja, nan, danmaku) [Default]"
  echo "  [2] Skip all subtitles"
  read -p "Enter number (Enter = default [1]): " SUB_STRATEGY
fi

# ==========================================
# === 6. THE OUTER LOOP (Process Videos) ===
# ==========================================
for (( idx=0; idx<TOTAL_VIDEOS; idx++ )); do
  VIDEO_URL="${PLAYLIST_URLS[$idx]}"
  UNIQUE_ID="$(date +"%Y%m%d_%H%M%S")_$(($RANDOM % 1000))"
  
  echo "================================================="
  echo "🎬 Processing ($((idx+1))/$TOTAL_VIDEOS): $VIDEO_URL"
  echo "================================================="

  # 6a. Get Info JSON for THIS video
  INFO_JSON_RAW="$(yt-dlp ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} --skip-download --dump-single-json "$VIDEO_URL" 2>/dev/null || true)"
  if [[ -z "$INFO_JSON_RAW" ]]; then
    echo "⚠️ Failed to get info for this video. Skipping..."
    continue
  fi
  INFO_JSON_PATH="${DOWNLOADS_DIR}/info_${UNIQUE_ID}.info.json"
  TEMP_FILES+=("$INFO_JSON_PATH")
  printf "%s" "$INFO_JSON_RAW" > "$INFO_JSON_PATH"

  # 6b. Chapters Logic
  WANT_CHAPTERS=false
  if jq -e '.chapters and (.chapters|length>0)' "$INFO_JSON_PATH" >/dev/null 2>&1; then
    echo "ℹ️ Detected $(jq '.chapters|length' "$INFO_JSON_PATH") chapters."
    WANT_CHAPTERS=true
  fi

  # 6c. Subtitle Logic
  SUB_ARGS=(); WANT_SUBS=false
  if [[ $TOTAL_VIDEOS -eq 1 ]]; then
    # Interactive mode for single video
    AVAILABLE=(); KINDS=(); LABELS=()
    for kind in subtitles automatic_captions; do
      while IFS= read -r code; do
        if [[ "$code" =~ ^(zh|en|ja|nan) ]]; then
          AVAILABLE+=("$code"); KINDS+=("${kind:0:4}"); LABELS+=("${code} (${kind:0:4})")
        fi
      done < <(jq -r "(.${kind} // {}) | keys[]?" "$INFO_JSON_PATH")
    done
    if jq -e '(.subtitles.danmaku // []) | length > 0' >/dev/null 2>&1 "$INFO_JSON_PATH"; then
      AVAILABLE+=("danmaku"); KINDS+=("dmk"); LABELS+=("danmaku (dmk)")
    fi
    if [[ ${#AVAILABLE[@]} -gt 0 ]]; then
      echo "✅ Available subtitle languages:"
      for i in "${!AVAILABLE[@]}"; do printf "  [%d] %s\n" $((i+1)) "${LABELS[$i]}"; done
      read -p "Enter numbers to download (e.g., 1,3 / 0 = skip / Enter = all best): " PICK
      LANG_SET=","; SUB_PICK_CODES=(); PICK_HAS_DMK=false
      if [[ -z "${PICK// /}" ]]; then
        for i in "${!AVAILABLE[@]}"; do
          lang="${AVAILABLE[$i]}"; [[ "${KINDS[$i]}" == "dmk" ]] && continue
          if ! contains_lang "$lang" "$LANG_SET"; then SUB_PICK_CODES+=("$lang"); LANG_SET="${LANG_SET}${lang},"; fi
        done
      else
        IFS=',' read -ra idxs <<<"$(echo "$PICK" | tr -d ' ')"
        for raw in "${idxs[@]}"; do
          [[ "$raw" =~ ^[0-9]+$ ]] || continue; j=$((raw-1)); [[ $j -lt 0 || $j -ge ${#AVAILABLE[@]} ]] && continue
          lang="${AVAILABLE[$j]}"; [[ "${KINDS[$j]}" == "dmk" ]] && { PICK_HAS_DMK=true; continue; }
          if ! contains_lang "$lang" "$LANG_SET"; then SUB_PICK_CODES+=("$lang"); LANG_SET="${LANG_SET}${lang},"; fi
        done
      fi
      [[ ${#SUB_PICK_CODES[@]} -gt 0 ]] && SUB_ARGS+=( --write-subs --convert-subs srt --sub-langs "$(IFS=,; echo "${SUB_PICK_CODES[*]}")" ) && WANT_SUBS=true
      [[ "$PICK_HAS_DMK" == true ]] && SUB_ARGS+=( --write-subs --sub-langs "danmaku" ) && WANT_SUBS=true
    fi
  else
    # Global auto-mode for playlists
    if [[ "$SUB_STRATEGY" != "2" ]]; then
      SUB_ARGS=( --write-subs --convert-subs srt --sub-langs "zh*,en*,ja*,nan*,danmaku" )
      WANT_SUBS=true
    fi
  fi

  # 6d. Download Pre-checks
  SANITIZED_FILENAME_BASE=$(yt-dlp --skip-download --load-info-json "$INFO_JSON_PATH" --print filename -o "${DOWNLOADS_DIR}/%(title)s" 2>/dev/null)
  FINAL_RENAMED_PATH="${SANITIZED_FILENAME_BASE}_${UNIQUE_ID}.${FINAL_TARGET_EXT}"
  TEMP_OUTPUT_TMPL="${DOWNLOADS_DIR}/${UNIQUE_ID}_TEMP.%(ext)s"
  
  COMMON_ARGS=( --merge-output-format "$MERGE_FORMAT" --write-thumbnail --output "$TEMP_OUTPUT_TMPL" )
  [[ "$FORCE_MP4_REMUX" == true ]] && COMMON_ARGS+=( --remux-video mp4 )

  echo "▶️ Downloading: $(basename "$FINAL_RENAMED_PATH")..."
  if ! yt-dlp ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} ${FORMAT_ARGS[@]+"${FORMAT_ARGS[@]}"} ${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"} ${SUB_ARGS[@]+"${SUB_ARGS[@]}"} "$VIDEO_URL"; then
     echo "❌ Download failed for this video. Skipping to next..."
     continue
  fi

  # 6e. Precise File Targeting
  FINAL_OUTPUT=""
  for ext in mp4 mkv webm; do
    if [[ -f "${DOWNLOADS_DIR}/${UNIQUE_ID}_TEMP.${ext}" ]]; then
      FINAL_OUTPUT="${DOWNLOADS_DIR}/${UNIQUE_ID}_TEMP.${ext}"
      break
    fi
  done
  if [[ -z "$FINAL_OUTPUT" ]]; then echo "⚠️ Target video file not found. Skipping..."; continue; fi

  THUMBNAIL_PATH=""
  for ext in webp jpg png; do
    if [[ -f "${DOWNLOADS_DIR}/${UNIQUE_ID}_TEMP.${ext}" ]]; then
      THUMBNAIL_PATH="${DOWNLOADS_DIR}/${UNIQUE_ID}_TEMP.${ext}"
      TEMP_FILES+=("$THUMBNAIL_PATH")
      break
    fi
  done

  # 6f. Danmaku Pre-processing
  ASS_PATH=""
  if command -v danmaku2ass >/dev/null && [[ -f "${DOWNLOADS_DIR}/${UNIQUE_ID}_TEMP.danmaku.xml" ]]; then
    XML_PATH="${DOWNLOADS_DIR}/${UNIQUE_ID}_TEMP.danmaku.xml"
    ASS_PATH="${XML_PATH%.xml}.ass"
    TEMP_FILES+=("$ASS_PATH" "$XML_PATH")
    VIDEO_RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$FINAL_OUTPUT" 2>/dev/null || echo "1920x1080")
    [[ "$VIDEO_RES" != *"x"* ]] && VIDEO_RES="1920x1080"
    echo "📝 Converting danmaku to ASS (${VIDEO_RES})..."
    danmaku2ass --size "${VIDEO_RES}" --font "PingFang SC" --fontsize 36 "$XML_PATH" -o "$ASS_PATH" >/dev/null 2>&1
  fi

  declare -a SRT_FILES=()
  while IFS= read -r -d $'\0'; do SRT_FILES+=("$REPLY"); done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -name "*_${UNIQUE_ID}_TEMP.*.srt" -print0)

  # 6g. Ffmpeg Merge
  echo "🎬 Ffmpeg Merging..."
  METADATA_TXT="${DOWNLOADS_DIR}/metadata_${UNIQUE_ID}.txt"
  FINAL_OUTPUT_PATH_TEMP="${DOWNLOADS_DIR}/${UNIQUE_ID}_META_TEMP.${FINAL_TARGET_EXT}"
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
      case "$lang_full" in zh-Hant) lang_code="zht";; zh-Hans|zh) lang_code="zho";; en) lang_code="eng";; ja) lang_code="jpn";; *) lang_code="${lang_full:0:3}";; esac
      FFMPEG_CODECS+=( -metadata:s:s:${SUB_IDX} "language=${lang_code}" )
      SUB_IDX=$((SUB_IDX + 1))
    done
  fi

  if [[ -n "$ASS_PATH" ]]; then
    ASS_CODEC="mov_text"; [[ "$FINAL_TARGET_EXT" == "mkv" ]] && ASS_CODEC="ass"
    FFMPEG_INPUTS+=( -i "$ASS_PATH" ); FFMPEG_MAPS+=( -map $((${#FFMPEG_INPUTS[@]}-1)) )
    FFMPEG_CODECS+=( -c:s:${SUB_IDX} "$ASS_CODEC" -metadata:s:s:${SUB_IDX} "language=und" -metadata:s:s:${SUB_IDX} "title=Danmaku" )
  fi

  ffmpeg -hide_banner -loglevel error "${FFMPEG_INPUTS[@]}" "${FFMPEG_MAPS[@]}" "${FFMPEG_CODECS[@]}" "${FFMPEG_META[@]}" "$FINAL_OUTPUT_PATH_TEMP"
  ffmpeg -hide_banner -loglevel error -i "$FINAL_OUTPUT_PATH_TEMP" -c copy -movflags +faststart "$FINAL_RENAMED_PATH"

  # 6h. Per-Loop Cleanup (Destroy Temp files for this video only)
  for f in "${TEMP_FILES[@]+"${TEMP_FILES[@]}"}"; do
    [[ -f "$f" ]] && rm -f "$f"
  done
  TEMP_FILES=() # Reset array for next loop
  rm -f "${DOWNLOADS_DIR}"/*_"${UNIQUE_ID}"_TEMP.*.srt 2>/dev/null || true
  rm -f "${DOWNLOADS_DIR}"/*_"${UNIQUE_ID}"_TEMP.danmaku.xml 2>/dev/null || true
  rm -f "${DOWNLOADS_DIR}/${UNIQUE_ID}_TEMP".* 2>/dev/null || true

  echo "✅ Saved: $(basename "$FINAL_RENAMED_PATH")"
  sleep 1 # Ensure UNIQUE_ID changes cleanly for the next loop
done

echo "---"
echo "🎉 All downloads complete! Location: ${DOWNLOADS_DIR}"
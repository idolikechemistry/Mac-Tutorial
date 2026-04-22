#!/bin/bash
# ===
# 20260422_1500:00
# V 4.0.1 (Pro & Refactored Edition)
# v40.1 Core:
# 1. Implemented global 'trap' for guaranteed automatic cleanup of temporary files.
# 2. Refactored into modular functions for better readability and maintainability.
# 3. Replaced risky 'ls -t' with precise extension matching for file targeting.
# ===
set -euo pipefail

# === 1. Globals & Configuration ===
DOWNLOADS_DIR="${HOME}/Downloads"
CURRENT_DATETIME="$(date +"%Y%m%d_%H%M%S")"
COOKIES_FILE="/opt/homebrew/yt-dlp_cookie_bilibili.txt"
TEMP_FILES=() # Array to track temporary files for trap cleanup

# Safe Cleanup Trap
cleanup() {
  echo "🧹 Executing automatic cleanup..."
  for f in "${TEMP_FILES[@]+"${TEMP_FILES[@]}"}"; do
    [[ -f "$f" ]] && rm -f "$f"
  done
  # Fallback wildcard cleanup for dynamic files
  rm -f "${DOWNLOADS_DIR}"/*_"${CURRENT_DATETIME}".*.srt 2>/dev/null || true
  rm -f "${DOWNLOADS_DIR}"/*_"${CURRENT_DATETIME}".danmaku.xml 2>/dev/null || true
  rm -f "${DOWNLOADS_DIR}/${CURRENT_DATETIME}_TEMP".* 2>/dev/null || true
}
trap cleanup EXIT

# === 2. Core Dependencies ===
check_dependencies() {
  for cmd in jq ffmpeg ffprobe; do
    if ! command -v "$cmd" >/dev/null; then
      echo "❌ Cannot find '$cmd'. Please install via Homebrew (brew install $cmd)."
      exit 1
    fi
  done
  if [[ "$VIDEO_URL" == *"bilibili.com"* ]] && ! command -v danmaku2ass >/dev/null; then
    echo "ℹ️ (Tip) 'danmaku2ass' not found. Bilibili danmaku will remain as .xml."
  fi
}

# Helper functions
supports_browser() { yt-dlp -h 2>/dev/null | grep -qiE "Supported browsers.*\b$1\b"; }
contains_lang() { case ",$2," in *,"$1",*) return 0;; *) return 1;; esac; }
try_dump_info() { yt-dlp "$@" ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} --skip-download --dump-single-json "$VIDEO_URL" 2>/dev/null || true; }
sanitize_ffmpeg_meta() { tr -d '\n\r' | sed 's/\\/\\\\/g; s/=/\\=/g; s/;/\\;/g; s/#/\\#/g'; }

# === 3. Cookie Detection & Info Extraction ===
get_video_info_and_cookies() {
  echo "🔎 Detecting video information and login status..."
  COOKIE_ARGS=()
  INFO_JSON_RAW=""

  if [[ "$IS_BILIBILI" == true ]]; then
    if [[ -f "$COOKIES_FILE" ]]; then
      INFO_JSON_RAW="$(try_dump_info --cookies "$COOKIES_FILE")" && COOKIE_ARGS=(--cookies "$COOKIES_FILE") || true
    fi
  else
    INFO_JSON_RAW="$(try_dump_info)" || true
    if [[ -z "$INFO_JSON_RAW" ]] && supports_browser safari; then
      INFO_JSON_RAW="$(try_dump_info --cookies-from-browser safari)" && COOKIE_ARGS=(--cookies-from-browser safari) || true
    fi
    # Chrome/Chromium/Arc Fallbacks
    if [[ -z "$INFO_JSON_RAW" ]]; then
      for browser in chrome chromium arc; do
        if supports_browser "$browser"; then
          INFO_JSON_RAW="$(try_dump_info --cookies-from-browser "$browser")" && { COOKIE_ARGS=(--cookies-from-browser "$browser"); break; } || true
        fi
      done
    fi
    if [[ -z "$INFO_JSON_RAW" ]] && [[ -f "$COOKIES_FILE" ]]; then
      INFO_JSON_RAW="$(try_dump_info --cookies "$COOKIES_FILE")" && COOKIE_ARGS=(--cookies "$COOKIES_FILE") || true
    fi
  fi

  [[ -z "$INFO_JSON_RAW" ]] && INFO_JSON_RAW="$(try_dump_info)" || true
  
  if [[ -z "$INFO_JSON_RAW" ]] || ! jq -e '.id' <<<"$INFO_JSON_RAW" >/dev/null 2>&1; then
    echo "❌ Failed to retrieve video information. URL may be wrong or cookie expired."
    exit 1
  fi

  echo "✅ Successfully retrieved video info (using ${COOKIE_ARGS[0]:-"no-cookie"})"
  INFO_JSON_PATH="${DOWNLOADS_DIR}/info_${CURRENT_DATETIME}.info.json"
  TEMP_FILES+=("$INFO_JSON_PATH")
  printf "%s" "$INFO_JSON_RAW" > "$INFO_JSON_PATH"
}

# === 4. Setup Execution Flow ===
read -p "Please enter video URL: " VIDEO_URL
SITE_ARGS=()
IS_BILIBILI=false
[[ "$(echo "$VIDEO_URL" | awk -F/ '{print $3}' | tr '[:upper:]' '[:lower:]')" == *"bilibili.com"* ]] && { SITE_ARGS+=( --referer "https://www.bilibili.com" ); IS_BILIBILI=true; }

check_dependencies
get_video_info_and_cookies

precheck_msg="$(yt-dlp ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} --simulate "$VIDEO_URL" 2>&1 || true)"
if echo "$precheck_msg" | grep -qiE '\[Piracy\]|Unsupported URL|no longer supported|No video could be found'; then
  echo "❌ This link currently cannot be processed by yt-dlp."
  exit 1
fi

# === 5. Subtitle & Chapter Logic ===
WANT_CHAPTERS=false
if jq -e '.chapters and (.chapters|length>0)' "$INFO_JSON_PATH" >/dev/null 2>&1; then
  echo "ℹ️ (v25) Detected $(jq '.chapters|length' "$INFO_JSON_PATH") chapters, will be embedded automatically."
  WANT_CHAPTERS=true
fi

AVAILABLE=(); KINDS=(); LABELS=()
echo "🔎 Filtering subtitles (only showing zh*, en*, ja*, nan*)..."
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

WANT_SUBS=false; SUB_PICK_CODES=(); PICK_HAS_DMK=false; SUB_ARGS=()
if [[ ${#AVAILABLE[@]} -gt 0 ]]; then
  echo "✅ Available subtitle languages:"
  for i in "${!AVAILABLE[@]}"; do printf "  [%d] %s\n" $((i+1)) "${LABELS[$i]}"; done
  read -p "Enter numbers to download (e.g., 1,3 / 0 = skip / Enter = all best): " PICK
  LANG_SET=","
  
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

# === 6. Quality & Formats ===
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

SANITIZED_FILENAME_BASE=$(yt-dlp ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} --skip-download --load-info-json "$INFO_JSON_PATH" --print filename -o "${DOWNLOADS_DIR}/%(title)s_${CURRENT_DATETIME}" 2>/dev/null)
FINAL_RENAMED_PATH="${SANITIZED_FILENAME_BASE}.${FINAL_TARGET_EXT}"
echo "ℹ️ Final file will be named: $(basename "$FINAL_RENAMED_PATH")"

# === 7. Download ===
TEMP_OUTPUT_TMPL="${DOWNLOADS_DIR}/${CURRENT_DATETIME}_TEMP.%(ext)s"
COMMON_ARGS=( --merge-output-format "$MERGE_FORMAT" --write-thumbnail --output "$TEMP_OUTPUT_TMPL" )
[[ "$FORCE_MP4_REMUX" == true ]] && COMMON_ARGS+=( --remux-video mp4 )

echo "▶️ Starting download..."
yt-dlp ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} ${FORMAT_ARGS[@]+"${FORMAT_ARGS[@]}"} ${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"} ${SUB_ARGS[@]+"${SUB_ARGS[@]}"} "$VIDEO_URL" || { echo "❌ Download failed."; exit 1; }

# Precise targeting instead of ls -t
FINAL_OUTPUT=""
for ext in mp4 mkv webm; do
  if [[ -f "${DOWNLOADS_DIR}/${CURRENT_DATETIME}_TEMP.${ext}" ]]; then
    FINAL_OUTPUT="${DOWNLOADS_DIR}/${CURRENT_DATETIME}_TEMP.${ext}"
    break
  fi
done
[[ -z "$FINAL_OUTPUT" ]] && { echo "⚠️ Output video not found."; exit 1; }

THUMBNAIL_PATH=""
for ext in webp jpg png; do
  if [[ -f "${DOWNLOADS_DIR}/${CURRENT_DATETIME}_TEMP.${ext}" ]]; then
    THUMBNAIL_PATH="${DOWNLOADS_DIR}/${CURRENT_DATETIME}_TEMP.${ext}"
    TEMP_FILES+=("$THUMBNAIL_PATH")
    break
  fi
done

# === 8. Danmaku Pre-processing ===
ASS_PATH=""
if command -v danmaku2ass >/dev/null && [[ -f "${DOWNLOADS_DIR}/${CURRENT_DATETIME}_TEMP.danmaku.xml" ]]; then
  XML_PATH="${DOWNLOADS_DIR}/${CURRENT_DATETIME}_TEMP.danmaku.xml"
  ASS_PATH="${XML_PATH%.xml}.ass"
  TEMP_FILES+=("$ASS_PATH" "$XML_PATH")
  VIDEO_RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$FINAL_OUTPUT" 2>/dev/null || echo "1920x1080")
  [[ "$VIDEO_RES" != *"x"* ]] && VIDEO_RES="1920x1080"
  echo "📝 Converting danmaku to ASS (${VIDEO_RES})..."
  danmaku2ass --size "${VIDEO_RES}" --font "PingFang SC" --fontsize 36 "$XML_PATH" -o "$ASS_PATH" >/dev/null 2>&1
fi

declare -a SRT_FILES=()
while IFS= read -r -d $'\0'; do SRT_FILES+=("$REPLY"); done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -name "*_${CURRENT_DATETIME}_TEMP.*.srt" -print0)

# === 9. Ffmpeg Metadata & Merge ===
echo "🎬 Preparing Ffmpeg final merge..."
METADATA_TXT="${DOWNLOADS_DIR}/metadata_${CURRENT_DATETIME}.txt"
FINAL_OUTPUT_PATH_TEMP="${DOWNLOADS_DIR}/${CURRENT_DATETIME}_META_TEMP.${FINAL_TARGET_EXT}"
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

echo "🚀 Phase 1: Merging content and embedding metadata..."
ffmpeg -hide_banner -loglevel error "${FFMPEG_INPUTS[@]}" "${FFMPEG_MAPS[@]}" "${FFMPEG_CODECS[@]}" "${FFMPEG_META[@]}" "$FINAL_OUTPUT_PATH_TEMP"

echo "⚙️ Phase 2: Forcing Faststart indexing..."
ffmpeg -hide_banner -loglevel error -i "$FINAL_OUTPUT_PATH_TEMP" -c copy -movflags +faststart "$FINAL_RENAMED_PATH"

# === 10. Completion ===
echo "---"
echo "✅ Download & Merge Complete!"
echo "   • Saved as : $(basename "$FINAL_RENAMED_PATH")"
echo "   • Location : ${DOWNLOADS_DIR}"
# Trap handles the rest of the cleanup!

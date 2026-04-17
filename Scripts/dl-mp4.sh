#!/bin/bash
# ===
# 20251104_2345:00
# V 3.9.0 (Execution Fix Edition)
# v39 Core:
# 1. Final version of the script after resolving all syntax and encoding issues (V33, V35, V36, V38).
# 2. Uses the "Two-Phase Ffmpeg Processing" strategy to ensure file preview capability.
# 3. All comments and user output are strictly ASCII (English).
# ===
# Enable strict mode: -e (exit on error), -u (error on unset variables), -o pipefail (exit on pipeline failure)
set -euo pipefail

# === 1. Basic Configuration ===
DOWNLOADS_DIR="${HOME}/Downloads"
CURRENT_DATETIME="$(date +"%Y%m%d_%H%M%S")"
# [v13 Core] Bilibili is forced to use this file; it serves as fallback for YouTube, etc.
COOKIES_FILE="/opt/homebrew/yt-dlp_cookie_bilibili.txt"

# v31 Check: jq is core to this script
if ! command -v jq >/dev/null; then
  echo "❌ Cannot find 'jq'."
  echo "   This tool is crucial for v39 metadata parsing."
  echo "   If you use Homebrew, please run:"
  echo "   brew install jq"
  exit 1
fi
# v30 Check: Ffmpeg and Ffprobe are core to this script
if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
  echo "❌ Cannot find 'ffmpeg' or 'ffprobe'."
  echo "   This tool is crucial for v39 merging and repair."
  echo "   If you use Homebrew, please run:"
  echo "   brew install ffmpeg"
  exit 1
fi
# v22 Check: Check for danmaku2ass if Bilibili danmaku is needed
if [[ "$*" == *"bilibili.com"* ]] && ! command -v danmaku2ass >/dev/null; then
   echo "ℹ️ (Tip) Cannot find 'danmaku2ass'. Bilibili danmaku will only be downloaded as .xml"
   echo "   (Run pip install danmaku2ass to enable ASS embedding)"
fi

read -p "Please enter video URL: " VIDEO_URL

# === 2. Source Site Specific Arguments ===
SITE_ARGS=()
IS_BILIBILI=false
HOST_LOWER="$(echo "$VIDEO_URL" | awk -F/ '{print $3}' | tr '[:upper:]' '[:lower:]')"
echo "🔎 Source: $HOST_LOWER"
# Bilibili needs referer
if [[ "$HOST_LOWER" == *"bilibili.com"* ]]; then
  SITE_ARGS+=( --referer "https://www.bilibili.com" )
  IS_BILIBILI=true
fi

# === 3. Helper Functions ===
supports_browser() { yt-dlp -h 2>/dev/null | grep -qiE "Supported browsers.*\b$1\b"; }
contains_lang() { case ",$2," in *,"$1",*) return 0;; *) return 1;; esac; }
try_dump_info_with () {
  local out
  out="$(yt-dlp "$@" ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} --skip-download --dump-single-json "$VIDEO_URL" 2>/dev/null || true)"
  if [[ -n "$out" ]] && jq -e '.id' >/dev/null 2>&1 <<<"$out"; then
    echo "$out"
    return 0
  fi
  return 1
}

# === 4. [v12 Core] Cookie Detection (Bilibili forces cookie.txt) ===
COOKIE_ARGS=()
INFO_JSON_RAW=""
echo "🔎 Detecting video information and login status..."

if [[ "$IS_BILIBILI" == true ]]; then
  # --- Bilibili dedicated logic ---
  echo "ℹ️ Detected Bilibili link, forcing use of $COOKIES_FILE"
  if [[ -f "$COOKIES_FILE" ]]; then
    INFO_JSON_RAW="$(try_dump_info_with --cookies "$COOKIES_FILE")" && \
      COOKIE_ARGS=(--cookies "$COOKIES_FILE") || true
  else
    echo "⚠️ Warning: Bilibili cookie file does not exist ($COOKIES_FILE)"
  fi
else
  # --- YouTube / Other sites logic (v6) ---
  # Try 1) No cookies
  INFO_JSON_RAW="$(try_dump_info_with)" || true
  # Try 2) Safari (if 1 failed)
  if [[ -z "$INFO_JSON_RAW" ]] && supports_browser safari; then
    echo "... Trying Safari cookie"
    INFO_JSON_RAW="$(try_dump_info_with --cookies-from-browser safari)" && \
      COOKIE_ARGS=(--cookies-from-browser safari) || true
  fi
  # Try 3) Chrome / Chromium (if 1, 2 failed)
  if [[ -z "$INFO_JSON_RAW" ]]; then
    CHROME_DIR="${HOME}/Library/Application Support/Google/Chrome"
    CHROMIUM_DIR="${HOME}/Library/Application Support/Chromium"
    CH_PROFILES=()
    if [[ -d "$CHROME_DIR" ]]; then while IFS= read -r p; do CH_PROFILES+=("chrome:$p"); done < <(ls -1 "$CHROME_DIR" | grep -E '^(Default|Profile [0-9]+)$' || true);
    elif [[ -d "$CHROMIUM_DIR" ]]; then while IFS= read -r p; do CH_PROFILES+=("chromium:$p"); done < <(ls -1 "$CHROMIUM_DIR" | grep -E '^(Default|Profile [0-9]+)$' || true); fi
    if [[ ${#CH_PROFILES[@]} -gt 0 ]]; then
      browser_name="${CH_PROFILES[0]%:*}"
      if supports_browser "$browser_name"; then
        for prof_arg in "${CH_PROFILES[@]}"; do
          echo "... Trying $prof_arg cookie"
          INFO_JSON_RAW="$(try_dump_info_with --cookies-from-browser "$prof_arg")" && \
            { COOKIE_ARGS=(--cookies-from-browser "$prof_arg"); break; } || true
        done
      fi
    fi
  fi
  # Try 4) Arc (if 1, 2, 3 failed)
  if [[ -z "$INFO_JSON_RAW" ]] && supports_browser arc; then
    ARC_DIR="${HOME}/Library/Application Support/Arc/User Data"
    ARC_PROFILES=()
    if [[ -d "$ARC_DIR" ]]; then
      while IFS= read -r p; do ARC_PROFILES+=("arc:$p"); done < <(ls -1 "$ARC_DIR" | grep -E '^(Default|Profile [0-9]+)$' || true)
    fi
    if [[ ${#ARC_PROFILES[@]} -gt 0 ]]; then
        for prof_arg in "${ARC_PROFILES[@]}"; do
          echo "... Trying $prof_arg cookie"
          INFO_JSON_RAW="$(try_dump_info_with --cookies-from-browser "$prof_arg")" && \
            { COOKIE_ARGS=(--cookies-from-browser "$prof_arg"); break; } || true
        done
    fi
  fi
  # Try 5) cookies.txt (non-Bilibili final fallback)
  if [[ -z "$INFO_JSON_RAW" ]] && -f "$COOKIES_FILE"; then
    echo "... Trying $COOKIES_FILE"
    INFO_JSON_RAW="$(try_dump_info_with --cookies "$COOKIES_FILE")" && \
      COOKIE_ARGS=(--cookies "$COOKIES_FILE") || true
  fi
fi

# (Common fallback) If all methods above failed (including Bilibili)
if [[ -z "$INFO_JSON_RAW" ]]; then
  echo "ℹ️ (Fallback) Trying to get info without cookie (logged-out state)..."
  INFO_JSON_RAW="$(try_dump_info_with)" || true
  COOKIE_ARGS=() # Ensure array is empty
fi

# Check result
if [[ -z "$INFO_JSON_RAW" ]]; then
  echo "❌ Failed to retrieve video information. URL may be wrong or cookie expired."
  exit 1
fi
echo "✅ Successfully retrieved video info (using ${COOKIE_ARGS[0]:-"no-cookie"})"
# v21: We need .info.json and .jpg, so force write
INFO_JSON_PATH="${DOWNLOADS_DIR}/info_${CURRENT_DATETIME}.info.json"
THUMBNAIL_PATH_TMPL="${DOWNLOADS_DIR}/thumbnail_${CURRENT_DATETIME}.%(ext)s"
printf "%s" "$INFO_JSON_RAW" > "$INFO_JSON_PATH"


# === 5. URL Pre-check ===
precheck_msg="$(yt-dlp ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} --simulate "$VIDEO_URL" 2>&1 || true)"
if echo "$precheck_msg" | grep -qiE '\[Piracy\]|Unsupported URL|This website is no longer supported|No video could be found'; then
  echo "❌ This link currently cannot be processed by yt-dlp:"
  echo "$precheck_msg" | sed -n '1,8p'
  rm -f "$INFO_JSON_PATH"
  exit 1
fi

# === 6. Chapter Detection (v25 automatic) ===
CHAPTER_COUNT=0
WANT_CHAPTERS=false
if jq -e '.chapters and (.chapters|length>0)' "$INFO_JSON_PATH" >/dev/null 2>&1; then
  CHAPTER_COUNT="$(jq '.chapters|length' "$INFO_JSON_PATH")"
  echo "ℹ️ (v25) Detected ${CHAPTER_COUNT} chapters, will be embedded automatically."
  WANT_CHAPTERS=true # v25: Automatically set to true
else
  echo "ℹ️ (v25) No chapters detected."
fi

# === 7. Subtitle Detection (v8: filter languages, including nan*) ===
AVAILABLE=()
KINDS=()
LABELS=()
echo "🔎 Filtering subtitles (only showing zh*, en*, ja*, nan*)..."
while IFS= read -r code; do
  if [[ "$code" == "zh"* || "$code" == "en"* || "$code" == "ja"* || "$code" == "nan"* ]]; then
    AVAILABLE+=("$code"); KINDS+=("sub"); LABELS+=("${code} (sub)")
  fi
done < <(jq -r '(.subtitles // {}) | keys[]?' "$INFO_JSON_PATH")
while IFS= read -r code; do
  if [[ "$code" == "zh"* || "$code" == "en"* || "$code" == "ja"* || "$code" == "nan"* ]]; then
    AVAILABLE+=("$code"); KINDS+=("auto"); LABELS+=("${code} (auto)")
  fi
done < <(jq -r '(.automatic_captions // {}) | keys[]?' "$INFO_JSON_PATH")
if jq -e '(.subtitles.danmaku // []) | length > 0' >/dev/null 2>&1 "$INFO_JSON_PATH"; then
  AVAILABLE+=("danmaku"); KINDS+=("dmk"); LABELS+=("danmaku (dmk)")
fi

# === 8. Subtitle Selection ===
WANT_SUBS=false
SUB_PICK_CODES=()
PICK_HAS_DMK=false
if [[ "${#AVAILABLE[@]}" -gt 0 ]]; then
  echo "✅ Available subtitle languages:"
  for i in "${!AVAILABLE[@]}"; do printf "  [%d] %s\n" $((i+1)) "${LABELS[$i]}"; done
  echo "([Enter] = select all best; 0 = skip subtitles; dmk not selected by default)"
  read -p "Please enter the numbers to download (can select multiple, e.g., 1,3 / 0 = skip): " PICK
  LANG_SET=","
  if [[ -z "${PICK// /}" ]]; then # Select all best
    for i in "${!AVAILABLE[@]}"; do [[ "${KINDS[$i]}" != "sub" ]] && continue; lang="${AVAILABLE[$i]}"; if ! contains_lang "$lang" "$LANG_SET"; then SUB_PICK_CODES+=("$lang"); LANG_SET="${LANG_SET}${lang},"; fi; done
    for i in "${!AVAILABLE[@]}"; do [[ "${KINDS[$i]}" != "auto" ]] && continue; lang="${AVAILABLE[$i]}"; if ! contains_lang "$lang" "$LANG_SET"; then SUB_PICK_CODES+=("$lang"); LANG_SET="${LANG_SET}${lang},"; fi; done
  else # Manual selection
    IFS=',' read -ra idxs <<<"$(echo "$PICK" | tr -d ' ')"; for raw in "${idxs[@]}"; do [[ "$raw" =~ ^[0-9]+$ ]] || continue; j=$((raw-1)); [[ $j -lt 0 || $j -ge ${#AVAILABLE[@]} ]] && continue; [[ "${KINDS[$j]}" == "sub" ]] || continue; lang="${AVAILABLE[$j]}"; if ! contains_lang "$lang" "$LANG_SET"; then SUB_PICK_CODES+=("$lang"); LANG_SET="${LANG_SET}${lang},"; fi; done
    for raw in "${idxs[@]}"; do [[ "$raw" =~ ^[0-9]+$ ]] || continue; j=$((raw-1)); [[ $j -lt 0 || $j -ge ${#AVAILABLE[@]} ]] && continue; [[ "${KINDS[$j]}" != "auto" ]] || continue; lang="${AVAILABLE[$j]}"; if ! contains_lang "$lang" "$LANG_SET"; then SUB_PICK_CODES+=("$lang"); LANG_SET="${LANG_SET}${lang},"; fi; done
    for raw in "${idxs[@]}"; do [[ "$raw" =~ ^[0-9]+$ ]] || continue; j=$((raw-1)); [[ $j -lt 0 || $j -ge ${#AVAILABLE[@]} ]] && continue; [[ "${KINDS[$j]}" == "dmk" ]] && PICK_HAS_DMK=true; done
  fi
  if [[ "${#SUB_PICK_CODES[@]}" -gt 0 || "$PICK_HAS_DMK" == true ]]; then WANT_SUBS=true; fi
else
  echo "ℹ️ No available subtitles detected (or no zh/en/ja/nan subs)."
fi

# === 8b. [v18 Core] Intelligent Quality Selection (Force Remux) ===
FORMAT_ARGS=()
MERGE_FORMAT=""
FORCE_MP4_REMUX=false 
FINAL_TARGET_EXT="mkv" # v22 added: default target

echo "✅ Please select your download goal:"
echo "  [1] Highest Quality Priority (e.g., 4K/8K, potentially .mkv)"
echo "  [2] Best Compatibility Priority (H.264/H.265, prioritize .mp4)"
read -p "Enter number (Enter = default [2] Best Compatibility): " PICK_GOAL

if [[ "$PICK_GOAL" == "1" ]]; then
  # --- Goal 1: Highest Quality Priority (MKV Preferred) ---
  echo "ℹ️ Strategy: Prioritizing highest quality (bv+ba)..."
  FORMAT_ARGS=( -f 'bv+ba / bv[vcodec~="^((avc)|(hvc)|(hev))"]+ba[ext=m4a]' )
  MERGE_FORMAT="mkv/mp4"
  FINAL_TARGET_EXT="mkv"
else
  # --- Goal 2: Best Compatibility Priority (MP4 Preferred) (Default) ---
  echo "ℹ️ Strategy: Prioritizing best compatibility (H.264/H.265), and forcing remux to .mp4..."
  FORMAT_ARGS=( -f 'bv[vcodec~="^((avc)|(hvc)|(hev))"]+ba[ext=m4a] / bv+ba' )
  MERGE_FORMAT="mp4/mkv"
  FORCE_MP4_REMUX=true
  FINAL_TARGET_EXT="mp4"
fi

# === 8c. Pre-fetch Final Filename (v29 Bugfix 2) ===
echo "🔎 (v29) Pre-fetching sanitized filename..."
# 1. This is our 'target' template, excluding extension
TARGET_FILENAME_TMPL="${DOWNLOADS_DIR}/%(title)s_${CURRENT_DATETIME}"
# 2. Call yt-dlp --print filename, reusing the downloaded info.json
SANITIZED_FILENAME_BASE=$(yt-dlp \
  ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} \
  ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} \
  --skip-download \
  --load-info-json "$INFO_JSON_PATH" \
  --print filename \
  -o "${TARGET_FILENAME_TMPL}" 2>/dev/null)

# 3. Combine to the final, clean path
FINAL_RENAMED_PATH="${SANITIZED_FILENAME_BASE}.${FINAL_TARGET_EXT}"
echo "ℹ️ Final file will be named: $(basename "$FINAL_RENAMED_PATH")"

# === 9. Assemble yt-dlp Arguments ===

# 9a. Subtitle Arguments (v21 fix)
SUB_ARGS=()
DANMAKU2ASS=false
if [[ "$WANT_SUBS" == true ]]; then
  if [[ "${#SUB_PICK_CODES[@]}" -gt 0 ]]; then
    SUB_JOIN="$(IFS=,; echo "${SUB_PICK_CODES[*]}")"
    # v21: Removed --embed-subs; we handle it manually in the Ffmpeg step
    SUB_ARGS+=( --write-subs --convert-subs srt --sub-langs "$SUB_JOIN" )
  fi
  if [[ "$PICK_HAS_DMK" == true ]]; then
    echo "ℹ️ Bilibili danmaku selected: will download .xml."
    SUB_ARGS+=( --write-subs --sub-langs "danmaku" )
    if command -v danmaku2ass >/dev/null; then
      DANMAKU2ASS=true
    else
      echo "（Tip: Install danmaku2ass to convert to .ass and embed; otherwise only XML is downloaded）"
    fi
  fi
fi

# 9b. Core Download Arguments (v29 fix)
# v29: Use temporary output name
TEMP_OUTPUT_TMPL="${DOWNLOADS_DIR}/${CURRENT_DATETIME}_TEMP.%(ext)s"
COMMON_ARGS=(
  --merge-output-format "$MERGE_FORMAT"
  # v21 Removed: --embed-thumbnail
  # v21 Removed: --embed-metadata
  --write-thumbnail --output "thumbnail:${THUMBNAIL_PATH_TMPL}"
  -o "$TEMP_OUTPUT_TMPL"
)
if [[ "$FORCE_MP4_REMUX" == true ]]; then
  COMMON_ARGS+=( --remux-video mp4 )
fi

# === 10. [v21 Core] Execute Download (Download Only) ===
echo "▶️ Starting download (Format: ${MERGE_FORMAT})..."
if [[ "$FORCE_MP4_REMUX" == true ]]; then
  echo "ℹ️ (v18) Forced MP4 remux is enabled..."
fi
echo "ℹ️ (v21) Native embedding disabled; manual merging will be performed after download..."

yt-dlp \
  ${COOKIE_ARGS[@]+"${COOKIE_ARGS[@]}"} \
  ${SITE_ARGS[@]+"${SITE_ARGS[@]}"} \
  ${FORMAT_ARGS[@]+"${FORMAT_ARGS[@]}"} \
  ${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"} \
  ${SUB_ARGS[@]+"${SUB_ARGS[@]}"} \
  "$VIDEO_URL" \
|| { echo "❌ Download failed (network issue, member video, or disk full)"; [[ -f "$INFO_JSON_PATH" ]] && rm -f "$INFO_JSON_PATH"; exit 1; }

# === 11. Locate Output Video File (v31 Bugfix) ===
# v31 Fix: Removed erroneous starting '*' from ls
FINAL_OUTPUT="$(ls -t "${DOWNLOADS_DIR}/${CURRENT_DATETIME}_TEMP".mp4 2>/dev/null | head -n1 || true)"
if [[ -z "${FINAL_OUTPUT}" || ! -f "${FINAL_OUTPUT}" ]]; then
  FINAL_OUTPUT="$(ls -t "${DOWNLOADS_DIR}/${CURRENT_DATETIME}_TEMP".mkv 2>/dev/null | head -n1 || true)"
fi
if [[ -z "${FINAL_OUTPUT}" || ! -f "${FINAL_OUTPUT}" ]]; then
  FINAL_OUTPUT="$(ls -t "${DOWNLOADS_DIR}/${CURRENT_DATETIME}_TEMP".* 2>/dev/null | head -n1 || true)"
fi

if [[ -z "${FINAL_OUTPUT}" || ! -f "${FINAL_OUTPUT}" ]]; then
  echo "⚠️ Could not locate output file. yt-dlp may have downloaded but script couldn't find it."
  [[ -f "$INFO_JSON_PATH" ]] && rm -f "$INFO_JSON_PATH"; exit 1
fi
echo "ℹ️ Original file: $(basename "$FINAL_OUTPUT")"

# v21: Locate downloaded thumbnail
THUMBNAIL_PATH="$(ls -t "${DOWNLOADS_DIR}"/thumbnail_"${CURRENT_DATETIME}".* 2>/dev/null | head -n1 || true)"

# === 12. [v32 Core] Danmaku and Subtitle (Pre-processing) ===
ASS_PATH="" # v22: Initialize ASS path
if [[ "$DANMAKU2ASS" == true ]]; then
  XML_PATH="$(ls -t "${DOWNLOADS_DIR}"/*_"${CURRENT_DATETIME}".danmaku.xml 2>/dev/null | head -n1 || true)"
  if [[ -n "$XML_PATH" && -f "$XML_PATH" ]]; then
    ASS_PATH="${XML_PATH%.xml}.ass" # v22: Store ASS path
    
    # v30 Bugfix: Use ffprobe to detect actual resolution
    echo "ℹ️ (v30) Using ffprobe to detect video actual resolution..."
    VIDEO_RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$FINAL_OUTPUT" 2>/dev/null || echo "1920x1080")
    if [[ -z "$VIDEO_RES" || ! "$VIDEO_RES" == *"x"* ]]; then
      echo "⚠️ (v30) ffprobe detection failed, falling back to 1920x1080."
      VIDEO_RES="1920x1080" # Final fallback
    fi

    echo "📝 Converting danmaku to ass (using ${VIDEO_RES} resolution)..."
    danmaku2ass --size "${VIDEO_RES}" --font "PingFang SC" --fontsize 36 "$XML_PATH" -o "$ASS_PATH"
  fi
fi

# v32 Bugfix: Fix `set -u` error
# Using 'declare -a' and find...-print0 is the safest modern bash practice
# It ensures SRT_FILES is an empty array, not an unset variable, when no files are found.
declare -a SRT_FILES=()
while IFS= read -r -d $'\0'; do
    SRT_FILES+=("$REPLY")
done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -name "*_${CURRENT_DATETIME}.*.srt" -print0)

# === 13. [v38 Core] Manual Embedding (Two-Phase Ffmpeg) ===
echo "🎬 (v29) Preparing Ffmpeg final merge..."
# Prepare temporary file paths (v38: added an intermediate file)
FINAL_OUTPUT_PATH_TEMP="${DOWNLOADS_DIR}/${CURRENT_DATETIME}_META_TEMP.${FINAL_TARGET_EXT}" # Intermediate file
FINAL_OUTPUT_PATH="${DOWNLOADS_DIR}/${CURRENT_DATETIME}_FINAL.${FINAL_TARGET_EXT}"          # Final destination file
METADATA_TXT="${DOWNLOADS_DIR}/metadata_${CURRENT_DATETIME}.txt"

# v27 Bugfix 1: Prepare Ffmpeg Metadata file
# v27 Added: Function to sanitize FFMETADATA1 special characters (=;\\#)
sanitize_ffmpeg_meta() {
  tr -d '\n\r' | sed 's/\\/\\\\/g; s/=/\\=/g; s/;/\\;/g; s/#/\\#/g'
}; # <--- V35 Fix: Added semicolon for robust function termination

# ⚠️ V36 Fix: Removed command grouping; using multi-line redirection
echo ";FFMETADATA1" > "$METADATA_TXT" # Overwrite file
# v27: Redirect jq output to sanitize_ffmpeg_meta function
echo "title=$(jq -r '.title // "N/A"' "$INFO_JSON_PATH" | sanitize_ffmpeg_meta)" >> "$METADATA_TXT"
echo "artist=$(jq -r '.uploader // "N/A"' "$INFO_JSON_PATH" | sanitize_ffmpeg_meta)" >> "$METADATA_TXT"
echo "comment=$(jq -r '.webpage_url // "N/A"' "$INFO_JSON_PATH" | sanitize_ffmpeg_meta)" >> "$METADATA_TXT"
echo "[DESCRIPTION]" >> "$METADATA_TXT"
# v29 Bugfix 1: Sanitize description tags (Append using >>)
jq -r '.description // "N/A"' "$INFO_JSON_PATH" \
| sed 's/\[CHAPTER\]/\[_CHAPTER_\]/g; s/\[STREAM\]/\[_STREAM_\]/g' >> "$METADATA_TXT"

# v25: Append chapters to the same Metadata file
if [[ "$WANT_CHAPTERS" == true ]]; then
  echo "📚 (v25) Appending chapters to Metadata..."
  jq -c '.chapters[]' "$INFO_JSON_PATH" | while read -r ch; do
    s="$(jq -r '.start_time' <<<"$ch")"; e="$(jq -r '.end_time' <<<"$ch")"
    
    # v28 Bugfix: Also sanitize chapter title (t)
    t_raw="$(jq -r '.title' <<<"$ch" | tr '\n\r' ' ' | sed 's/[]\[\"]//g')"
    t="$(echo "$t_raw" | sanitize_ffmpeg_meta)" # v28 Fix
    
    s_ms=$(awk -v s="$s" 'BEGIN{printf "%.0f\n", s * 1000}')
    e_ms=$(awk -v e="$e" 'BEGIN{printf "%.0f\n", e * 1000}')
    # Append chapter block (note the >> )
    printf "[CHAPTER]\nTIMEBASE=1/1000\nSTART=%s\nEND=%s\ntitle=%s\n" "$s_ms" "$e_ms" "$t" >> "$METADATA_TXT"
  done
fi

# Prepare Ffmpeg argument array (v23)
FFMPEG_INPUTS=( -i "$FINAL_OUTPUT" )       # Input 0: Video
FFMPEG_MAPS=( -map 0 )                     # Map video (includes video and audio)
FFMPEG_CODECS=( -c copy )                  # Default: Copy all streams
FFMPEG_METADATA_FILES=( )                  
FFMPEG_SUB_STREAMS=0                       

# (Input 1) Add Metadata (includes chapters)
FFMPEG_INPUTS+=( -i "$METADATA_TXT" )
FFMPEG_METADATA_FILES+=( -map_metadata 1 ) # Map Metadata (from Input 1)

# (Input 2) Add Thumbnail (if exists)
if [[ -n "$THUMBNAIL_PATH" && -f "$THUMBNAIL_PATH" ]]; then
  FFMPEG_INPUTS+=( -i "$THUMBNAIL_PATH" )
  FFMPEG_MAPS+=( -map 2 ) # Map Thumbnail (from Input 2)
  FFMPEG_CODECS+=( -c:v:1 mjpeg -disposition:v:1 attached_pic )
else
  echo "ℹ️ (v33) Thumbnail not found, skipping embedding."
fi

# (Input 3+) Add SRT Subtitles (v33 Core Fix: Avoid set -u error)
if [[ ${#SRT_FILES[@]} -gt 0 ]]; then 
  echo "ℹ️ (v33) Detected ${#SRT_FILES[@]} SRT subtitle files ready for embedding."
  SUB_CODEC="mov_text"
  [[ "$FINAL_TARGET_EXT" == "mkv" ]] && SUB_CODEC="srt"
  for srt_file in "${SRT_FILES[@]}"; do
    FFMPEG_INPUTS+=( -i "$srt_file" )
    FFMPEG_MAPS+=( -map $((${#FFMPEG_INPUTS[@]}-1)) ) 
    FFMPEG_CODECS+=( -c:s:${FFMPEG_SUB_STREAMS} "$SUB_CODEC" )
    
    # ... (Language code detection logic remains unchanged) ...
    lang_full=$(basename "$srt_file" .srt | rev | cut -d. -f1 | rev)
    case "$lang_full" in
      zh-Hant)
        lang_code="zht" ;; # Traditional Chinese (Common in MP4)
      zh-Hans|zh)
        lang_code="zho" ;; # Simplified Chinese (ISO 639-2)
      en)
        lang_code="eng" ;;
      ja)
        lang_code="jpn" ;;
      *)
        lang_code="${lang_full:0:3}" ;; # Fallback: Take first three characters
    esac
    
    FFMPEG_CODECS+=( -metadata:s:s:${FFMPEG_SUB_STREAMS} "language=${lang_code}" )
    FFMPEG_SUB_STREAMS=$((FFMPEG_SUB_STREAMS + 1))
  done
fi

# (Input 4+) Add ASS Danmaku
if [[ -n "$ASS_PATH" && -f "$ASS_PATH" ]]; then
  ASS_CODEC="mov_text"
  [[ "$FINAL_TARGET_EXT" == "mkv" ]] && ASS_CODEC="ass"
  
  FFMPEG_INPUTS+=( -i "$ASS_PATH" )
  FFMPEG_MAPS+=( -map $((${#FFMPEG_INPUTS[@]}-1)) ) 
  FFMPEG_CODECS+=( -c:s:${FFMPEG_SUB_STREAMS} "$ASS_CODEC" )
  FFMPEG_CODECS+=( -metadata:s:s:${FFMPEG_SUB_STREAMS} "language=und" -metadata:s:s:${FFMPEG_SUB_STREAMS} "title=Danmaku" )
  FFMPEG_SUB_STREAMS=$((FFMPEG_SUB_STREAMS + 1))
fi

# --- V38 Phase 1: Merge All Content to Temporary File ---
echo "🚀 Executing Ffmpeg Phase 1: Merging content and embedding metadata (to ${FINAL_OUTPUT_PATH_TEMP})..."
# V38: Remove -movflags +faststart, let Phase 2 handle it
ffmpeg -hide_banner -loglevel error \
  "${FFMPEG_INPUTS[@]}" \
  "${FFMPEG_MAPS[@]}" \
  "${FFMPEG_CODECS[@]}" \
  "${FFMPEG_METADATA_FILES[@]}" \
  "$FINAL_OUTPUT_PATH_TEMP" # Output to intermediate temporary file

# --- V38 Phase 2: Execute Clean Faststart ---
echo "⚙️ Executing Ffmpeg Phase 2: Forcing Faststart indexing (to ${FINAL_OUTPUT_PATH})..."
ffmpeg -hide_banner -loglevel error \
  -i "$FINAL_OUTPUT_PATH_TEMP" \
  -c copy \
  -movflags +faststart \
  "$FINAL_OUTPUT_PATH"

# Replace old file (v23: delete original)
rm -f "$FINAL_OUTPUT" # Delete yt-dlp original temp file
FINAL_OUTPUT="$FINAL_OUTPUT_PATH"
echo "✅ (v38) Ffmpeg final merge complete."


# === 14. Cleanup (v38 Fix: Clean up all temporary files) ===
echo "🧹 Cleaning up temporary files..."
[[ -f "$INFO_JSON_PATH" ]] && rm -f "$INFO_JSON_PATH"
[[ -f "$METADATA_TXT" ]] && rm -f "$METADATA_TXT"
[[ -n "$THUMBNAIL_PATH" && -f "$THUMBNAIL_PATH" ]] && rm -f "$THUMBNAIL_PATH"
[[ -n "$ASS_PATH" && -f "$ASS_PATH" ]] && rm -f "$ASS_PATH"
[[ -f "$FINAL_OUTPUT_PATH_TEMP" ]] && rm -f "$FINAL_OUTPUT_PATH_TEMP" # V38: Cleanup intermediate temp file
rm -f "${DOWNLOADS_DIR}"/*_"${CURRENT_DATETIME}".*.srt
rm -f "${DOWNLOADS_DIR}"/*_"${CURRENT_DATETIME}".danmaku.xml
rm -f "${DOWNLOADS_DIR}/${CURRENT_DATETIME}_TEMP".* mv -f "$FINAL_OUTPUT" "$FINAL_RENAMED_PATH"
FINAL_OUTPUT="$FINAL_RENAMED_PATH"


# === 15. Completion ===
echo "---"
echo "✅ Download complete: $(basename "$FINAL_OUTPUT")"
echo "   • File Format: .${FINAL_TARGET_EXT}"
echo "   • Saved to: ${DOWNLOADS_DIR}"
echo "   • Embedded: Metadata, Thumbnail (v38 Ffmpeg manual)"
[[ ${#SRT_FILES[@]} -gt 0 ]] && echo "   • Embedded: ${#SRT_FILES[@]} SRT subtitle track(s)"
[[ "$PICK_HAS_DMK" == true ]] && echo "   • Embedded: Bilibili Danmaku (v32 actual resolution)"
[[ "$WANT_CHAPTERS" == true ]] && echo "   • Embedded: Video Chapters (v32 automatic)"

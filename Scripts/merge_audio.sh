#!/bin/zsh

# ==========================================
# 1. 系統依賴檢查
# ==========================================
for cmd in ffmpeg ffprobe MP4Box AtomicParsley awk bc perl; do
    command -v $cmd &> /dev/null || { echo "❌ 嚴重錯誤：缺少工具 $cmd。"; exit 1; }
done

# ==========================================
# 2. 變數與路徑初始化
# ==========================================
OUTPUT_NAME="merge"
OUTPUT_MEDIA="${OUTPUT_NAME}.m4a"
OUTPUT_SRT="${OUTPUT_NAME}.srt"
OUTPUT_LRC="${OUTPUT_NAME}.lrc"
CURRENT_DIR="$PWD"
TMP_DIR=$(mktemp -d)

trap 'rm -rf "$TMP_DIR"' EXIT

CONCAT_LIST="$TMP_DIR/files.txt"
CHAP_FILE="$TMP_DIR/chapters.txt"
MERGED_AAC="$TMP_DIR/merged.aac"

# 建立純淨 LRC 標頭
printf "[ti:Combined ASMR Audio]\n[re:Ultimate Visual Parser]\n[ve:11.0]\n" > "$CURRENT_DIR/$OUTPUT_LRC"
# 初始化 SRT 暫存
RAW_SRT_BUILD="$TMP_DIR/raw_build.srt"
> "$RAW_SRT_BUILD"

# --- 封面圖處理邏輯 ---
FINAL_COVER_PATH=""
FOUND_IMAGE=""
for ext in jpg jpeg png webp; do
    if [[ -f "cover.$ext" ]]; then
        FOUND_IMAGE="cover.$ext"
        if [[ "$ext" == "webp" ]]; then
            echo "🖼️ 偵測到 WebP 封面，正在轉碼為 JPEG..."
            ffmpeg -v error -y -i "$FOUND_IMAGE" -q:v 2 "$TMP_DIR/cover_converted.jpg"
            FINAL_COVER_PATH="$TMP_DIR/cover_converted.jpg"
        else
            FINAL_COVER_PATH="$CURRENT_DIR/$FOUND_IMAGE"
        fi
        break
    fi
done

# ==========================================
# 3. 核心模組：VTT 轉 LRC 解析器 (處理多行合併與序號過濾)
# ==========================================
convert_vtt_to_lrc() {
    local vtt_in="$1"
    local offset="$2"
    perl -ne '
        BEGIN { $offset = '$offset'; $time_tag = ""; $text = ""; }
        s/\r//g; s/<[^>]*>//g;
        if (/^WEBVTT/ || /^\s*$/ || /^\s*\d+\s*$/) { next; }
        if (/^(?:(\d{1,2}):)?(\d{2}):(\d{2})[\.\,](\d{3})\s*-->/) {
            if ($time_tag ne "") { print "$time_tag$text\n"; }
            my $h=$1?$1+0:0; my $m=$2+0; my $s=$3+0; my $ms=$4+0;
            my $total_sec = ($h*3600)+($m*60)+$s+($ms/1000)+$offset;
            my $new_m=int($total_sec/60); my $new_s=$total_sec-($new_m*60);
            $time_tag = sprintf("[%02d:%05.2f]", $new_m, $new_s); $text = "";
        } elsif ($time_tag ne "") {
            s/^\s+|\s+$//g; $text .= ($text eq "" ? "" : " ") . $_;
        }
        END { if ($time_tag ne "") { print "$time_tag$text\n"; } }
    ' "$vtt_in"
}

# ==========================================
# 4. 檔案遍歷與注入管線
# ==========================================
AUDIO_FILES=()
while IFS= read -r file; do
    AUDIO_FILES+=("$file")
done < <(find "$CURRENT_DIR" -maxdepth 1 -type f \( -name "*.wav" -o -name "*.mp3" -o -name "*.m4a" -o -name "*.flac" \) | LC_ALL=C sort)

CURRENT_TIME_SEC_FLOAT=0
CURRENT_TIME_MS=0
count=0

echo "🚀 開始執行「精簡章節 + 自動修復」封裝流程..."

for f in "${AUDIO_FILES[@]}"; do
    BASENAME=$(basename "$f")
    TITLE="${BASENAME%.*}"
    ((count++))

    DURATION_SEC=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f")
    DURATION_MS=$(awk "BEGIN {print int($DURATION_SEC * 1000)}")

    # A. 注入精簡版視覺化章節 (LRC) - 移除「第幾章」字樣
    M_LRC=$(awk "BEGIN {print int($CURRENT_TIME_SEC_FLOAT / 60)}")
    S_LRC=$(awk "BEGIN {print $CURRENT_TIME_SEC_FLOAT - ($M_LRC * 60)}")
    printf "[%02d:%05.2f]%s\n" $M_LRC $S_LRC "$TITLE" >> "$CURRENT_DIR/$OUTPUT_LRC"

    # B. 注入精簡版視覺化章節 (SRT 區塊)
    H_SRT=$(awk "BEGIN {printf \"%02d\", int($CURRENT_TIME_SEC_FLOAT/3600)}")
    M_SRT=$(awk "BEGIN {printf \"%02d\", int(($CURRENT_TIME_SEC_FLOAT%3600)/60)}")
    S_SRT=$(awk "BEGIN {printf \"%02d\", int($CURRENT_TIME_SEC_FLOAT%60)}")
    MS_SRT=$(awk "BEGIN {printf \"%03d\", int(($CURRENT_TIME_SEC_FLOAT*1000)%1000)}")

    END_TIME=$(echo "$CURRENT_TIME_SEC_FLOAT + 3.0" | bc)
    EH_SRT=$(awk "BEGIN {printf \"%02d\", int($END_TIME/3600)}")
    EM_SRT=$(awk "BEGIN {printf \"%02d\", int(($END_TIME%3600)/60)}")
    ES_SRT=$(awk "BEGIN {printf \"%02d\", int($END_TIME%60)}")
    EMS_SRT=$(awk "BEGIN {printf \"%03d\", int(($END_TIME*1000)%1000)}")

    printf "999\n%s:%s:%s,%s --> %s:%s:%s,%s\n【 %s 】\n\n" \
        $H_SRT $M_SRT $S_SRT $MS_SRT $EH_SRT $EM_SRT $ES_SRT $EMS_SRT "$TITLE" >> "$RAW_SRT_BUILD"

    # C. 處理原始字幕 - 【修正 itsoffset 順序】
    VTT_PATH=""
    [[ -f "${CURRENT_DIR}/${BASENAME}.vtt" ]] && VTT_PATH="${CURRENT_DIR}/${BASENAME}.vtt"
    [[ -f "${CURRENT_DIR}/${TITLE}.vtt" ]] && VTT_PATH="${CURRENT_DIR}/${TITLE}.vtt"

    if [ -n "$VTT_PATH" ]; then
        convert_vtt_to_lrc "$VTT_PATH" "$CURRENT_TIME_SEC_FLOAT" >> "$CURRENT_DIR/$OUTPUT_LRC"
        # 重要：-itsoffset 必須在 -i 之前
        ffmpeg -v error -itsoffset "$CURRENT_TIME_SEC_FLOAT" -i "$VTT_PATH" -f srt - >> "$RAW_SRT_BUILD"
        HAS_ANY_SUB=1
    fi

    # D. 建立章節 Metadata (M4A 內部)
    FORMATTED_TIME=$(awk -v ms="$CURRENT_TIME_MS" 'BEGIN {
        h = int(ms / 3600000); rem = ms % 3600000;
        m = int(rem / 60000); rem = rem % 60000;
        s = int(rem / 1000); ms_rem = rem % 1000;
        printf "%02d:%02d:%02d.%03d", h, m, s, ms_rem
    }')
    echo "CHAPTER$(printf "%02d" $count)=$FORMATTED_TIME" >> "$CHAP_FILE"
    echo "CHAPTER$(printf "%02d" $count)NAME=$TITLE" >> "$CHAP_FILE"

    # E. 音軌轉碼
    TMP_WAV="$TMP_DIR/part_${count}.wav"
    ffmpeg -v error -y -i "$f" -ar 44100 -ac 2 -c:a pcm_s16le "$TMP_WAV" &
    echo "file '$TMP_WAV'" >> "$CONCAT_LIST"

    CURRENT_TIME_MS=$((CURRENT_TIME_MS + DURATION_MS))
    CURRENT_TIME_SEC_FLOAT=$(echo "$CURRENT_TIME_SEC_FLOAT + $DURATION_SEC" | bc)
    printf "\r⏳ 正在處理: %d/%d" "$count" "${#AUDIO_FILES[@]}"
done

wait
echo -e "\n📦 正在執行合併與編號修復..."

# 合併音訊
ffmpeg -v warning -y -f concat -safe 0 -i "$CONCAT_LIST" -c:a aac -b:a 256k "$MERGED_AAC"

# F. SRT 重新編號邏輯 (解決多重 headers 與序號衝突)
if [ "$HAS_ANY_SUB" -eq 1 ]; then
    awk '
        BEGIN { idx = 1; }
        /^[0-9]+$/ {
            getline next_line;
            if (next_line ~ /-->/) {
                print idx++;
                print next_line;
                next;
            } else {
                # 如果不是時間軸，可能只是台詞中的數字，原樣印出
                print $0;
                print next_line;
                next;
            }
        }
        /^WEBVTT/ { next; } # 移除多餘標頭
        { print $0; }
    ' "$RAW_SRT_BUILD" > "$CURRENT_DIR/$OUTPUT_SRT"
fi

# MP4Box 封裝
MP4BOX_CMD=(MP4Box -quiet -new "$OUTPUT_MEDIA" -add "$MERGED_AAC" -chap "$CHAP_FILE")
[ "$HAS_ANY_SUB" -eq 1 ] && MP4BOX_CMD+=(-add "$CURRENT_DIR/$OUTPUT_SRT:lang=zho:name=Chinese")
[ -n "$FINAL_COVER_PATH" ] && MP4BOX_CMD+=(-itags cover="$FINAL_COVER_PATH")
"${MP4BOX_CMD[@]}"

# AtomicParsley 注入歌詞
[ "$HAS_ANY_SUB" -eq 1 ] && AtomicParsley "$OUTPUT_MEDIA" --lyricsFile "$CURRENT_DIR/$OUTPUT_LRC" --overWrite > /dev/null

echo "================================================="
echo "✅ 處理完成！"
echo "🎵 輸出檔案：$OUTPUT_MEDIA"
echo "🖼️ 封面相容：已處理 ${FOUND_IMAGE:-無}"
echo "📝 章節格式：■ 音訊檔名 (移除「第幾章」)"
echo "================================================="

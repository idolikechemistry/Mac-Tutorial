#!/usr/bin/env zsh

# --- 設定 ---
OUTPUT_FILE="output.m4a"
OUTPUT_SRT="${OUTPUT_FILE%.*}.srt"
OUTPUT_EXT_LRC="${OUTPUT_FILE%.*}.lrc"
OUTPUT_STD_LRC="${OUTPUT_FILE}.lrc"

TEMP_DIR=".tmp_process"
LOG_FILE="process.log"

# [核心修正] 讓腳本動態取得自身所在的目錄，不再依賴執行時的工作目錄
SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
VTT_PROCESSOR_SCRIPT="$SCRIPT_DIR/vtt_processor.py"

# --- 顏色設定 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 錯誤與清理機制 ---
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT INT TERM

check_deps() {
    local deps=("ffmpeg" "ffprobe" "MP4Box" "python3" "bc")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}錯誤: 未找到 $dep。請安裝依賴。${NC}"
            exit 1
        fi
    done
    if [ ! -f "$VTT_PROCESSOR_SCRIPT" ]; then
        echo -e "${RED}錯誤: 找不到 Python 解析器 '$VTT_PROCESSOR_SCRIPT'。${NC}"
        exit 1
    fi
    if ! python3 -c "import mutagen" &> /dev/null; then
        echo -e "${RED}錯誤: 尚未安裝 Mutagen。請執行 'pip3 install mutagen'。${NC}"
        exit 1
    fi
}

setup() {
    rm -rf "$TEMP_DIR" 2>/dev/null
    mkdir -p "$TEMP_DIR"
    touch "$TEMP_DIR/full.srt"
    touch "$TEMP_DIR/full.lrc"
    touch "$TEMP_DIR/full_ext.lrc"
    echo -e "${CYAN}開始處理影音合併與標籤注入任務...${NC}"
}

check_deps
setup

# --- 1. 資源檢索 ---
audio_files=( *.(wav|mp3)(Nn) )

if [ ${#audio_files[@]} -eq 0 ]; then
    echo -e "${RED}未找到音訊檔案 (.wav/.mp3)${NC}"
    exit 1
fi

# 取得第一張封面圖片
cover_imgs=( cover.(jpg|jpeg|png|webp)(Nn) )
cover_img="${cover_imgs[1]}"

# [新增] 針對 WebP 封面的終極相容性處理
if [[ "${cover_img:l}" == *.webp ]]; then
    echo -e "${YELLOW}提示: 偵測到 WebP 封面。為確保 Apple/iOS 設備相容性，正在自動轉換為 JPG...${NC}"
    # 使用 ffmpeg 將 webp 轉為 jpg，並存放在暫存區
    ffmpeg -y -i "$cover_img" "$TEMP_DIR/cover_converted.jpg" -loglevel error
    # 將封面變數指向轉換後的高相容性 JPG
    cover_img="$TEMP_DIR/cover_converted.jpg"
fi

# --- 2 & 3. 音訊合併與字幕處理 ---
echo "正在準備與標準化音訊格式..."
concat_list="$TEMP_DIR/concat_list.txt"
chapters_file="$TEMP_DIR/chapters.txt"
full_lrc="$TEMP_DIR/full.lrc"
full_ext_lrc="$TEMP_DIR/full_ext.lrc"
full_srt="$TEMP_DIR/full.srt"

cumulative_time=0.0
chapter_count=1
srt_counter=1

for f in "${audio_files[@]}"; do
    filename=$(basename "$f")
    name="${filename%.*}"
    echo "處理檔案: $filename"

    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f")

    temp_audio="norm_${chapter_count}.wav"
    ffmpeg -y -i "$f" -ar 44100 -ac 2 "$TEMP_DIR/$temp_audio" -loglevel error
    echo "file '$temp_audio'" >> "$concat_list"

    formatted_time=$(python3 -c "import datetime; print(str(datetime.timedelta(seconds=float($cumulative_time)))[:11])")
    echo "CHAPTER${chapter_count}=${formatted_time}" >> "$chapters_file"
    echo "CHAPTER${chapter_count}NAME=${name}" >> "$chapters_file"

    if [ -f "${filename}.vtt" ]; then
        target_vtt="${filename}.vtt"
    elif [ -f "${name}.vtt" ]; then
        target_vtt="${name}.vtt"
    else
        target_vtt=""
    fi

    if [ -n "$target_vtt" ]; then
        # [修正] 移除原本的 "./"，直接使用絕對路徑變數
        srt_counter=$(python3 "$VTT_PROCESSOR_SCRIPT" "$target_vtt" "$cumulative_time" "$srt_counter" "$full_srt" "$full_lrc" "$full_ext_lrc")
        if [ $? -ne 0 ]; then
        echo -e "${YELLOW}警告: 處理 $target_vtt 時發生錯誤。${NC}"
        fi
    else
        echo -e "${YELLOW}提示: 未找到對應的 VTT 檔案，跳過字幕處理。${NC}"
    fi

    cumulative_time=$(echo "$cumulative_time + $duration" | bc)
    chapter_count=$((chapter_count + 1))
done

# --- 執行 FFmpeg 合併音訊 ---
echo "執行 FFmpeg 合併音訊與 AAC 轉碼..."
cd "$TEMP_DIR" || exit 1
ffmpeg -f concat -safe 0 -i "concat_list.txt" -c:a aac -b:a 256k "merged.aac" -y &> "../$LOG_FILE"
cd ..

# --- 4. MP4Box 基礎封裝 ---
echo "正在使用 MP4Box 封裝容器..."
mp4box_args=("MP4Box" "-add" "$TEMP_DIR/merged.aac")
mp4box_args+=("-chap" "$chapters_file")

itags_str="tool=MergeScript"

if [ -n "$cover_img" ]; then
    itags_str="${itags_str}:cover=$cover_img"
fi

mp4box_args+=("-itags" "$itags_str")

if [ -s "$full_srt" ]; then
    mp4box_args+=("-add" "${full_srt}:lang=zh:group=2:name=Subtitle")
fi

mp4box_args+=("-new" "$OUTPUT_FILE")

"${mp4box_args[@]}" >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ 錯誤: MP4Box 封裝失敗。請檢查 process.log 了解詳情。${NC}"
    exit 1
fi

# --- 5. Mutagen 寫入精準 \xA9lyr 標籤 ---
if [ -s "$full_ext_lrc" ]; then
    echo "正在使用 Mutagen 注入高相容性動態歌詞..."
    python3 -c "
import sys
from mutagen.mp4 import MP4

try:
    video = MP4('$OUTPUT_FILE')
    with open('$full_ext_lrc', 'r', encoding='utf-8') as f:
        video['\xa9lyr'] = f.read()
    video.save()
except Exception as e:
    print(f'寫入歌詞標籤失敗: {e}', file=sys.stderr)
    sys.exit(1)
"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 動態歌詞已無損注入 M4A 標籤${NC}"
    else
        echo -e "${YELLOW}⚠️ 警告: 歌詞標籤寫入失敗，但主要影音已封裝完成。${NC}"
    fi
fi

# --- 6. 多軌實體備份 ---
echo -e "${GREEN}🎉 完成！高相容性音訊已輸出至: $OUTPUT_FILE${NC}"

if [ -s "$full_srt" ]; then
    cp "$full_srt" "$OUTPUT_SRT"
    echo -e "${GREEN}✅ 實體 SRT 字幕檔已備份至: $OUTPUT_SRT${NC}"
fi

# [修正] 將擴充版存為主要 LRC
if [ -s "$full_ext_lrc" ]; then
    cp "$full_ext_lrc" "$OUTPUT_EXT_LRC"
    echo -e "${GREEN}✅ 擴充版 LRC [hh:mm:ss.xx] 已備份至: $OUTPUT_EXT_LRC${NC}"
fi

# [修正] 將標準版存為備用 LRC
if [ -s "$full_lrc" ]; then
    cp "$full_lrc" "$OUTPUT_STD_LRC"
    echo -e "${GREEN}✅ 標準版 LRC [mm:ss.xx] 已備份至: $OUTPUT_STD_LRC${NC}"
fi

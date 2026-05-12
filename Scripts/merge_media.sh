#!/usr/bin/env zsh

# --- 設定 ---
# 取得當前所在資料夾的名稱 (例如：盤古)
DIR_NAME=$(basename "$PWD")

# 最終輸出的檔案名稱設定
OUTPUT_FILE="${DIR_NAME}.m4a"
OUTPUT_SRT="${DIR_NAME}.srt"
OUTPUT_LRC="${DIR_NAME}.lrc"  # 直接使用資料夾名稱作為唯一 LRC 檔名

TEMP_DIR=".tmp_process"
LOG_FILE="process.log"

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
    touch "$TEMP_DIR/orig_files.txt"
    echo -e "${CYAN}開始處理高相容性無損影音合併與標籤注入任務...${NC}"
}

check_deps
setup

# --- 1. 資源檢索、最高取樣率與音質規格偵測 (痛點 A) ---
audio_files=( *.(wav|mp3|m4a)(Nn) )

if [ ${#audio_files[@]} -eq 0 ]; then
    echo -e "${RED}未找到音訊檔案 (.wav/.mp3/.m4a)${NC}"
    exit 1
fi

echo "正在掃描音訊以偵測最高取樣率與編碼規格..."
MAX_SR=44100
USE_ALAC=false # 預設不使用無損編碼

for f in "${audio_files[@]}"; do
    echo "$f" >> "$TEMP_DIR/orig_files.txt" # 記錄原始檔案供後續 Metadata 繼承使用

    # 1. 偵測最高取樣率
    sr=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$f")
    if [[ -n "$sr" ]] && (( sr > MAX_SR )); then
        MAX_SR=$sr
    fi

    # 2. 偵測編碼格式 (判斷是否有高規格無損音訊)
    codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$f")
    # 如果發現 pcm (WAV 的核心), alac 或 flac，就觸發無損開關
    if [[ "${codec:l}" == *"pcm"* ]] || [[ "${codec:l}" == "alac" ]] || [[ "${codec:l}" == "flac" ]]; then
        USE_ALAC=true
    fi
done
echo -e "${GREEN}決定統一取樣率為: ${MAX_SR} Hz${NC}"

# 根據偵測結果，設定對應的 FFmpeg 編碼參數
if [ "$USE_ALAC" = true ]; then
    echo -e "${GREEN}🎵 偵測到高規格無損音訊來源，最終合併將啟用 ALAC 封裝！${NC}"
    ENCODE_ARGS=("-c:a" "alac")
else
    echo -e "${GREEN}🎧 來源為一般音質，最終合併將使用 AAC 256k 以確保最佳容量！${NC}"
    ENCODE_ARGS=("-c:a" "aac" "-b:a" "256k")
fi

# 取得第一張封面圖片並標準化 (痛點 C)
# --- 封面處理 (自動降級與提取機制) ---
# 1. 先尋找資料夾中是否有名為 cover 的圖片檔
cover_imgs=( cover.(jpg|jpeg|png|webp)(Nn) )
cover_img="${cover_imgs[1]}"

# 2. 如果沒有實體 cover 檔，嘗試從第一個音訊檔提取內建封面
if [ -z "$cover_img" ]; then
    first_audio="${audio_files[1]}"
    echo -e "${YELLOW}未找到實體 cover 檔案，嘗試從 '$first_audio' 提取內建封面...${NC}"
    extracted_cover="$TEMP_DIR/extracted_cover.jpg"

    # 嘗試使用 ffmpeg 提取影像流。-an 代表不處理音訊，-map 0:v 選擇影像流
    ffmpeg -y -i "$first_audio" -an -map 0:v:0 "$extracted_cover" -loglevel error 2>/dev/null

    # 檢查是否成功提取出檔案且大小不為 0
    if [ -s "$extracted_cover" ]; then
        cover_img="$extracted_cover"
        echo -e "${GREEN}✅ 成功從音訊提取封面。${NC}"
    fi
fi

# 3. 執行標準化處理 (若有封面才執行)
if [ -n "$cover_img" ]; then
    echo -e "${YELLOW}提示: 正在標準化封面圖片 (最高 3000px, 轉換為 JPG)...${NC}"
    # 將圖片縮放限制在 3000px 內，並統一轉為 jpg 確保相容性
    ffmpeg -y -i "$cover_img" -vf "scale='min(3000,iw)':'min(3000,ih)':force_original_aspect_ratio=decrease" -q:v 2 "$TEMP_DIR/cover_converted.jpg" -loglevel error
    cover_img="$TEMP_DIR/cover_converted.jpg"
else
    # 4. 如果都沒有，就留空，後續的 mp4box 會自動忽略封面嵌入
    echo -e "${YELLOW}提示: 均未找到實體或內建封面，本次封裝將不嵌入封面。${NC}"
fi

# --- 2 & 3. 中繼 WAV 生成與精準時間軸處理 (痛點 B) ---
echo "正在準備與標準化音訊格式 (轉為實體 WAV 以確保時間精度)..."
concat_list="$TEMP_DIR/concat_list.txt"
chapters_file="$TEMP_DIR/chapters.txt"
full_lrc="$TEMP_DIR/full.lrc"
full_ext_lrc="$TEMP_DIR/full_ext.lrc"
full_srt="$TEMP_DIR/full.srt"

cumulative_time=0.000000
chapter_count=1
srt_counter=1

for f in "${audio_files[@]}"; do
    filename=$(basename "$f")
    name="${filename%.*}"
    echo "處理檔案: $filename"

    temp_audio="norm_${chapter_count}.wav"
    # 強制重採樣為 Max Sample Rate 的 PCM 實體檔
    ffmpeg -y -i "$f" -ar "$MAX_SR" -ac 2 -c:a pcm_s16le "$TEMP_DIR/$temp_audio" -loglevel error
    echo "file '$temp_audio'" >> "$concat_list"

    # 從「實體 WAV」讀取精準時長，避免編碼器延遲
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TEMP_DIR/$temp_audio")

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
        srt_counter=$(python3 "$VTT_PROCESSOR_SCRIPT" "$target_vtt" "$cumulative_time" "$srt_counter" "$full_srt" "$full_lrc" "$full_ext_lrc")
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}警告: 處理 $target_vtt 時發生錯誤。${NC}"
        fi
    else
        echo -e "${YELLOW}提示: 未找到對應的 VTT 檔案，跳過字幕處理。${NC}"
    fi

    # 使用 bc -l 進行高精度浮點數運算
    cumulative_time=$(echo "$cumulative_time + $duration" | bc -l)
    chapter_count=$((chapter_count + 1))
done

# --- 4. 執行 FFmpeg 智慧合併 ---
echo "執行 FFmpeg 合併音訊與動態轉碼..."
cd "$TEMP_DIR" || exit 1

# 使用陣列變數 ${ENCODE_ARGS[@]} 來動態決定是 alac 還是 aac
ffmpeg -f concat -safe 0 -i "concat_list.txt" "${ENCODE_ARGS[@]}" "merged.m4a" -y &> "../$LOG_FILE"
cd ..

# --- 5. MP4Box 基礎封裝 ---
echo "正在使用 MP4Box 封裝容器..."
mp4box_args=("MP4Box" "-add" "$TEMP_DIR/merged.m4a")
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

# --- 6. Mutagen 寫入 Metadata 瀑布流與精準標籤 (痛點 D) ---
echo "正在使用 Mutagen 進行 Metadata 瀑布式繼承與動態歌詞注入..."

python3 - "$OUTPUT_FILE" "$full_ext_lrc" "$TEMP_DIR/orig_files.txt" << 'EOF'
import sys
import mutagen
from mutagen.mp4 import MP4

output_file = sys.argv[1]
ext_lrc_file = sys.argv[2]
orig_files_list = sys.argv[3]

# 升級版：針對 M4A 深度讀取擴充欄位 (Comment, Description, Synopsis)
def get_standard_tags(filepath):
    tags = {}
    try:
        f = mutagen.File(filepath)
        if f is None:
            return tags

        # 如果是 M4A (MP4 容器)，直接讀取底層原子標籤
        if type(f).__name__ == 'MP4':
            tags['title'] = f.get('\xa9nam', [None])[0]
            tags['artist'] = f.get('\xa9ART', [None])[0]
            tags['album'] = f.get('\xa9alb', [None])[0]
            tags['date'] = f.get('\xa9day', [None])[0]
            tags['genre'] = f.get('\xa9gen', [None])[0]
            tags['comment'] = f.get('\xa9cmt', [None])[0]
            tags['description'] = f.get('desc', [None])[0]
            tags['synopsis'] = f.get('syno', [None])[0]
        else:
            # 兼容 MP3 的 Fallback 處理
            from mutagen.easyid3 import EasyID3
            try:
                ef = EasyID3(filepath)
                tags['title'] = ef.get('title', [None])[0]
                tags['artist'] = ef.get('artist', [None])[0]
                tags['album'] = ef.get('album', [None])[0]
                tags['date'] = ef.get('date', [None])[0]
                tags['genre'] = ef.get('genre', [None])[0]
            except:
                pass
    except Exception:
        pass

    return {k: v for k, v in tags.items() if v is not None}

try:
    final_tags = {}
    # 瀑布式繼承：遍歷原始檔案列表
    with open(orig_files_list, 'r', encoding='utf-8') as flist:
        for line in flist:
            filepath = line.strip()
            if filepath:
                file_tags = get_standard_tags(filepath)
                for k, v in file_tags.items():
                    if k not in final_tags: # 最先出現的值為主
                        final_tags[k] = v

    video = MP4(output_file)

    # 寫入繼承的標籤 (包含 YouTube 長文與註解)
    if 'title' in final_tags: video['\xa9nam'] = final_tags['title']
    if 'artist' in final_tags: video['\xa9ART'] = final_tags['artist']
    if 'album' in final_tags: video['\xa9alb'] = final_tags['album']
    if 'date' in final_tags: video['\xa9day'] = final_tags['date']
    if 'genre' in final_tags: video['\xa9gen'] = final_tags['genre']
    if 'comment' in final_tags: video['\xa9cmt'] = final_tags['comment']
    if 'description' in final_tags: video['desc'] = final_tags['description']
    if 'synopsis' in final_tags: video['syno'] = final_tags['synopsis']

    # 寫入歌詞
    try:
        with open(ext_lrc_file, 'r', encoding='utf-8') as f_lrc:
            lyr_content = f_lrc.read()
            if lyr_content.strip():
                video['\xa9lyr'] = lyr_content
    except FileNotFoundError:
        pass

    video.save()
    print("✅ Metadata 與歌詞標籤已無損注入 M4A")
except Exception as e:
    print(f"⚠️ 標籤寫入失敗: {e}", file=sys.stderr)
EOF

# --- 7. 多軌實體備份 ---
echo -e "${GREEN}🎉 完成！高相容性無損音訊已輸出至: $OUTPUT_FILE${NC}"

# 備份實體 SRT
if [ -s "$full_srt" ]; then
    cp "$full_srt" "$OUTPUT_SRT"
    echo -e "${GREEN}✅ 實體 SRT 字幕檔已備份至: $OUTPUT_SRT${NC}"
fi

# [修正] 只保留高精度擴充版作為唯一的實體 LRC 備份
if [ -s "$full_ext_lrc" ]; then
    cp "$full_ext_lrc" "$OUTPUT_LRC"
    echo -e "${GREEN}✅ 高精度 LRC [hh:mm:ss.xx] 已備份至: $OUTPUT_LRC${NC}"
fi

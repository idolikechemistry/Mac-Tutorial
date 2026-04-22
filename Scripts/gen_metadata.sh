#!/bin/bash

# 初始化中繼檔
echo ";FFMETADATA1" > metadata.txt

current_time=0

# 按照檔名順序處理 .wav 與 .mp3 檔案
# 注意：這裡會排除 .vtt 檔案
for file in *.wav *.mp3; do
    if [ -f "$file" ]; then
        # 取得檔案時長（秒，含小數點）
        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file")
        
        # 轉換為毫秒 (ms) 以確保章節精確
        duration_ms=$(python3 -c "print(int(float('$duration') * 1000))")
        start_time=$current_time
        end_time=$((current_time + duration_ms))
        
        # 寫入章節資訊
        echo "" >> metadata.txt
        echo "[CHAPTER]" >> metadata.txt
        echo "TIMEBASE=1/1000" >> metadata.txt
        echo "START=$start_time" >> metadata.txt
        echo "END=$end_time" >> metadata.txt
        echo "title=${file%.*}" >> metadata.txt
        
        # 累加目前時間
        current_time=$end_time
        
        # 同時產生 FFmpeg 合併用的清單
        echo "file '$file'" >> inputs.txt
    fi
done

echo "完成！已產生 metadata.txt 與 inputs.txt"

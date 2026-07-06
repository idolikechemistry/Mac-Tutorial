#!/bin/bash

# 取得當下時間標記（格式：YYYYMMDD-HHMMSS）
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# 設定輸出檔案名稱
OUTPUT_FILE="merge_${TIMESTAMP}.md"

# 建立新的輸出檔案
> "$OUTPUT_FILE"

# 尋找當前目錄下所有的 .md 檔案（排除即將輸出的檔案），並依照檔名排序
find . -maxdepth 1 -name "*.md" ! -name "$OUTPUT_FILE" | sort | while read -r file; do
    # 取得純檔名（去除路徑符號如 ./）
    filename=$(basename "$file")

    # 寫入二級標題與空行
    echo "## $filename" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    # 將該子檔案的內容附加到輸出檔中
    cat "$file" >> "$OUTPUT_FILE"

    # 在每個檔案內容結束後加上額外的空行，確保 Markdown 排版不會擠在一起
    echo "" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
done

echo "合併完成！所有內容已匯出至：$OUTPUT_FILE"

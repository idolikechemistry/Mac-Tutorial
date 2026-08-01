#!/bin/bash

CURRENT_DIR="$(pwd)"
DIR_NAME="$(basename "$CURRENT_DIR")"
OUTPUT_PDF="${CURRENT_DIR}/${DIR_NAME}.pdf"

# 1. 取得圖檔並排序
mapfile -t files < <(find . -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.tiff" -o -iname "*.bmp" \) | sort -f)

if [ ${#files[@]} -eq 0 ]; then
    echo "❌ 錯誤：當前目錄下沒有找到支援的圖片檔案！"
    exit 1
fi

echo "📂 找到 ${#files[@]} 個圖片檔案，開始進行 1:1 無損合併..."

# 2. 直接將原圖封裝成 PDF (不設定 -resize, -extent 或 -density)
/opt/homebrew/bin/magick "${files[@]}" "$OUTPUT_PDF"

echo "✅ 合併完成！輸出檔案：${DIR_NAME}.pdf"

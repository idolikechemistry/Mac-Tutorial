#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title dl-audio
# @raycast.mode fullOutput
# @raycast.icon 🎧
# @raycast.description 下載 YouTube 音訊為 mp3 或 m4a，兼容單支影片與播放清單
# @raycast.argument1 { "type": "text", "placeholder": "貼上網址", "secure": false }
# @raycast.argument2 { "type": "dropdown", "placeholder": "格式選擇", "data": [{"title": "原生無損 (M4A)", "value": "m4a"}, {"title": "高相容 (MP3 320k)", "value": "mp3"}] }

# Ver 20260427 (Amphibious Edition)

set -euo pipefail

# === 1. 初始化變數與環境 (雙棲邏輯) ===
# 使用 ${var:-} 賦予空值預設，避免終端機裸跑時觸發 unbound variable 錯誤
VIDEO_URL="${1:-}"
AUDIO_FORMAT="${2:-}"

# 如果 VIDEO_URL 是空的，代表這是在終端機手動執行，啟動互動模式
if [[ -z "$VIDEO_URL" ]]; then
  echo "🎧 歡迎使用 YouTube 音訊下載器 (Terminal 模式)"
  read -r -p "🔗 請貼上影片或播放清單網址: " VIDEO_URL
  
  if [[ -z "$VIDEO_URL" ]]; then
    echo "❌ 網址不能為空，腳本終止！"
    exit 1
  fi
  
  # 詢問格式
  echo "🎵 請選擇目標格式："
  echo "  [1] 原生無損 (M4A) [預設]"
  echo "  [2] 高相容 (MP3 320k)"
  read -r -p "請輸入數字 (1/2，直接按 Enter 為預設 1): " FORMAT_CHOICE
  
  if [[ "$FORMAT_CHOICE" == "2" ]]; then
    AUDIO_FORMAT="mp3"
  else
    AUDIO_FORMAT="m4a"
  fi
fi

DOWNLOADS_DIR="${HOME}/Downloads"

# 檢查必要依賴 (僅需 yt-dlp 與 ffmpeg)
for cmd in yt-dlp ffmpeg; do
  if ! command -v "$cmd" >/dev/null; then 
    echo "❌ 錯誤：未安裝 $cmd，請透過 Homebrew 安裝 (brew install $cmd)。"
    exit 1
  fi
done

echo "🔍 分析網址結構與格式要求..."

# === 2. 核心通用參數 ===
DL_ARGS=(
  --ignore-errors
  --no-overwrites
  --embed-thumbnail
  --embed-metadata
  --convert-thumbnails jpg
  --restrict-filenames
  --paths "$DOWNLOADS_DIR"
  # 自動略過影片中的業配、片頭片尾互動，確保純音訊體驗最佳化
  --sponsorblock-remove "sponsor,intro,outro"
)

# === 3. 格式與章節處理邏輯 ===
if [[ "$AUDIO_FORMAT" == "m4a" ]]; then
  echo "🎵 目標格式：M4A (嘗試原生提取並嵌入章節)"
  DL_ARGS+=( 
    --format "bestaudio[ext=m4a]/140/bestaudio" 
    --extract-audio 
    --audio-format m4a 
    --embed-chapters 
  )
else
  echo "🎵 目標格式：MP3 320k (不支援章節嵌入)"
  DL_ARGS+=( 
    --format "bestaudio" 
    --extract-audio 
    --audio-format mp3 
    --audio-quality "320k" 
  )
fi

# === 4. 單支影片 vs 播放清單 路徑與命名邏輯 ===
# 透過快速解析 JSON 來判斷是否為清單，不實際下載內容
if yt-dlp --flat-playlist --dump-single-json "$VIDEO_URL" 2>/dev/null | grep -q '"_type": "playlist"'; then
  echo "📚 偵測為播放清單，將建立專屬資料夾並自動排序..."
  # 格式：Downloads/清單名稱/01-影片標題_20260427_112000.m4a
  DL_ARGS+=( --output "%(playlist_title|channel)s/%(playlist_index)02d-%(title)s_%(epoch>%Y%m%d_%H%M%S)s.%(ext)s" )
else
  echo "🎬 偵測為單支影片..."
  # 格式：Downloads/影片標題_20260427_112000.m4a
  DL_ARGS+=( --output "%(title)s_%(epoch>%Y%m%d_%H%M%S)s.%(ext)s" )
fi

# === 5. 執行下載與除錯回退機制 ===
echo "=========================================="
echo "▶️ 開始下載程序..."

if ! yt-dlp "${DL_ARGS[@]}" "$VIDEO_URL"; then
  echo "⚠️ 下載遇到阻礙 (可能為年齡限制或會員專屬)，嘗試調用 Safari 登入狀態 (Cookie) 進行突破..."
  if ! yt-dlp --cookies-from-browser safari "${DL_ARGS[@]}" "$VIDEO_URL"; then
    echo "❌ 最終下載失敗。請檢查網址有效性、網路狀態，或手動確認影片是否需要付費訂閱。"
    exit 1
  fi
fi

echo "=========================================="
echo "✅ 任務完成！檔案已安全存入 ${DOWNLOADS_DIR}"
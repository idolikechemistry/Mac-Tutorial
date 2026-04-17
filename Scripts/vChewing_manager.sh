#!/bin/bash

# ==========================================
# 📂 唯音輸入法 (vChewing) 備份路徑設定區
# ==========================================
APP_ID="org.atelierInmu.inputmethod.vChewing"
BACKUP_ROOT="$HOME/my_documents/Github/my_vChewing-dic"
SRC_DATA="$HOME/Library/Containers/org.atelierInmu.inputmethod.vChewing/Data/Library/Application Support/vChewing"
SRC_PREF="$HOME/Library/Preferences/${APP_ID}.plist"

# ==========================================
# 🚀 功能 1：備份到 GitHub (Backup)
# ==========================================
do_backup() {
    echo "🔄 開始備份..."
    mkdir -p "$BACKUP_ROOT"

    if [ -d "$SRC_DATA" ]; then
        echo "📂 正在複製使用者詞庫與符號檔..."
        cp "$SRC_DATA"/*.txt "$BACKUP_ROOT/" 2>/dev/null
        cp "$SRC_DATA"/symbols.dat "$BACKUP_ROOT/" 2>/dev/null
    else
        echo "⚠️ 找不到詞庫資料夾，略過詞庫備份。"
    fi

    echo "⚙️ 正在匯出系統設定檔..."
    defaults export "$APP_ID" "$BACKUP_ROOT/${APP_ID}.plist"

    echo "☁️ 準備上傳至 GitHub..."
    cd "$BACKUP_ROOT" || exit
    
    if [ -n "$(git status --porcelain)" ]; then
        git add .
        git commit -m "Auto-backup: $(date '+%Y-%m-%d %H:%M:%S')"
        git push
        echo "✅ 備份完成！已成功推送到 GitHub。"
    else
        echo "✨ 檔案沒有變動，無須推送到 GitHub。"
    fi
}

# ==========================================
# 📥 功能 2：從 GitHub 還原 (Restore) + 下載資料夾防護網
# ==========================================
do_restore() {
    echo "🔄 開始還原..."
    cd "$BACKUP_ROOT" || exit
    
    # 1. 從 GitHub 拉取最新進度
    echo "☁️ 正在從 GitHub 下載最新備份..."
    git pull

    # ==========================================
    # 🛡️ 新增：比對差異，並將衝突檔案移至「下載」
    # ==========================================
    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    DOWNLOAD_DIR="$HOME/Downloads"
    HAS_DIFF=false

    echo "🔍 檢查本地詞庫與雲端版本的差異..."
    for local_file in "$SRC_DATA"/*.txt "$SRC_DATA"/symbols.dat; do
        if [ -f "$local_file" ]; then
            filename=$(basename "$local_file")
            remote_file="$BACKUP_ROOT/$filename"

            # 如果 GitHub 沒有這個檔，或檔案內容不同，則觸發保護
            if [ ! -f "$remote_file" ] || ! cmp -s "$local_file" "$remote_file"; then
                HAS_DIFF=true
                extension="${filename##*.}" # 取得副檔名
                name="${filename%.*}"       # 取得主檔名
                dest_file="$DOWNLOAD_DIR/${name}_${TIMESTAMP}.${extension}"
                
                # 直接將有差異的本地檔案「移動」到下載資料夾
                mv "$local_file" "$dest_file"
                echo "⚠️ 發現差異！已將本地檔案移至：$dest_file"
            fi
        fi
    done

    if [ "$HAS_DIFF" = false ]; then
        echo "✨ 本地詞庫與雲端版本一致，無衝突檔案。"
    fi
    # ==========================================

    # 2. 強制關閉唯音輸入法
    echo "🛑 正在關閉唯音輸入法進程..."
    pkill -f "vChewing"

    # 3. 還原系統設定檔
    if [ -f "$BACKUP_ROOT/${APP_ID}.plist" ]; then
        echo "⚙️ 正在匯入系統設定檔..."
        defaults import "$APP_ID" "$BACKUP_ROOT/${APP_ID}.plist"
    fi

    # 4. 還原詞庫與符號檔
    echo "📂 正在覆蓋使用者詞庫與符號檔..."
    mkdir -p "$SRC_DATA"
    cp "$BACKUP_ROOT"/*.txt "$SRC_DATA/" 2>/dev/null
    cp "$BACKUP_ROOT"/symbols.dat "$SRC_DATA/" 2>/dev/null

    echo "✅ 還原完成！請隨意切換一下中英文，喚醒唯音輸入法即可套用新設定。"
}

# ==========================================
# 🎮 主選單控制台
# ==========================================
clear
echo "===================================="
echo "  🎹 唯音輸入法 (vChewing) 資料管家  "
echo "===================================="
echo "  1) 📤 備份設定與詞庫到 GitHub"
echo "  2) 📥 從 GitHub 還原設定與詞庫"
echo "  3) ❌ 離開"
echo "===================================="
read -p "請輸入選項 (1/2/3): " choice

case $choice in
    1) do_backup ;;
    2) do_restore ;;
    3) echo "👋 掰掰！" ; exit 0 ;;
    *) echo "⚠️ 錯誤的選項" ; exit 1 ;;
esac
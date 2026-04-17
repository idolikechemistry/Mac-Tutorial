#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Open btop in Tab (Auto Top-Right)
# @raycast.mode silent
# @raycast.description Open btop and dynamically calculate top-right corner.

osascript -e '
-- 1. 跟 Finder 拿當前螢幕的寬度
tell application "Finder"
    set screenBounds to bounds of window of desktop
    set screenWidth to item 3 of screenBounds
end tell

-- 2. 啟動並設定終端機 (不變)
tell application "Terminal"
    activate
    if not (exists window 1) then
        do script "btop"
    else
        tell application "System Events" to keystroke "t" using command down
        delay 0.4
        do script "btop" in window 1
    end if
    delay 0.5
    set number of columns of window 1 to 90
    set number of rows of window 1 to 26
end tell

-- 3. 動態計算位置並移動
tell application "System Events"
    tell process "Terminal"
        -- 取得剛剛設定好 80x24 的視窗實際寬度 (包含外框)
        set winSize to size of window 1
        set winWidth to item 1 of winSize
        
        -- 計算右上角 X 座標：螢幕寬度 - 視窗寬度
        set targetX to (screenWidth - winWidth)
        
        -- 移動視窗 (Y 軸維持 0 貼齊頂部)
        set position of window 1 to {targetX, 0}
    end tell
end tell'

echo "已動態計算並移至右上角！"
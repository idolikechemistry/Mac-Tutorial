# Scripts Dashboard 1

> **Scripts overview:** 以下為 `Scripts/` 下每個 `.sh` 腳本的功能、依賴與啟動方式。

| 腳本檔名 | 主要功能 | 依賴工具 | 啟動命令 |
|---|---|---|---|
| `backup_zsh.sh` | 備份 `~/.zshrc` 和 `~/.p10k.zsh` 到 iCloud TextEdit 文件資料夾 | 內建 Bash 工具 | `bash Scripts/backup_zsh.sh` |
| `dl-audio.sh` | 下載 YouTube 音訊並可選擇 mp3 或 m4a，支援 chapters 嵌入 | `yt-dlp`, `ffmpeg`, `jq` | `bash Scripts/dl-audio.sh` |
| `dl-mp4.sh` | 下載影片/音訊、處理字幕、輸出兼容格式（mp4/mkv） | `yt-dlp`, `ffmpeg`, `ffprobe`, `jq`, 可選 `danmaku2ass` | `bash Scripts/dl-mp4.sh` |
| `embed_youtube_chapters.sh` | 從 YouTube 下載章節 metadata，並將章節與封面嵌入指定影片/音訊檔 | `yt-dlp`, `ffmpeg`, `jq` | `bash Scripts/embed_youtube_chapters.sh` |
| `krokiet.sh` | 啟動 Krokiet macOS 應用程式 | `macOS Terminal` / `bash` | `bash Scripts/krokiet.sh` |
| `lyrics-md2srt.sh` | 將帶時間戳記的歌詞 Markdown 轉換為 SRT 字幕檔 | `awk` | `bash Scripts/lyrics-md2srt.sh <input>.md` |
| `terminal-btop-90*26.sh` | 透過 AppleScript 開啟 Terminal 並在右上角運行 `btop` | `osascript`, `btop`, Terminal.app | `bash Scripts/terminal-btop-90*26.sh` |
| `vChewing_manager.sh` | 備份/還原 vChewing 詞庫與設定，並推送/拉取 GitHub | `git`, `defaults`, `pkill`, `bash` | `bash Scripts/vChewing_manager.sh` |

> **注意事項:**
> - `dl-mp4.sh` 會基於網址自動檢測來源並嘗試使用瀏覽器 cookie 或 cookies.txt。
> - `terminal-btop-90*26.sh` 需要 macOS Terminal.app 以及 `btop` 可用。
> - `vChewing_manager.sh` 會讀寫 `$HOME` 下的 vChewing 相關設定與備份資料夾。

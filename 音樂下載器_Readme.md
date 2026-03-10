---
up: 
aliases: 
today:
  - "[[20241110_週日]]"
description: 
tags:
---
---
此腳本需要執行則需要有 yt-dlp 及 ffmpeg 這兩個程式的幫助
我們可以透過 Homebrew 來安裝並管理他們
首先

---
## 安裝 Homebrew：

打開 Mac 內的「終端機. app」並且輸入：
```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
接著終端會跑一陣子，直到他顯示安裝完成
最終的安裝位址應該會在 /opt/homebrew 
但 /opt 預設是被系統隱藏的資料夾，可使用以下指令將系統隱藏的資料夾顯示出來：

###### 暫時顯示/隱藏檔案夾：

「Shift」 + 「Command」 + 「.」

###### 永久顯示所有隱藏資料夾：
```
defaults write com.apple.finder AppleShowAllFiles TRUE
```
then
```
killall Finder
```
若要改回預設的隱藏模式，將第一條的 TRUE 改為 FALSE 即可
若要在終端機隱藏特定資料夾：
```
chflags hidden
```
並且將欲隱藏之資料夾拖至終端機中以完成檔案路徑後，按 Enter

---
## 安裝 yt-dlp 及 ffmpeg：

安裝完 Homebrew 之後，在終端中執行：
```
brew install yt-dlp
```
以及
```
brew install ffmpeg
```
來安裝這兩個套件
完成後這兩個套件應該會被安裝在 /opt/homebrew/bin/ 的目錄中

---

接著我們需要建立可以在終端機中執行下載功能的腳本以及可以讓 Automator 呼叫這兩個腳本的腳本

---
## 建立 Shell 檔案
### 1. 使用 touch 命令建立 Shell 檔案

1. 打開終端機（Terminal）。
2. 輸入以下命令來建立新的 Shell 檔案，假設檔案路徑為 `/opt/homebrew/bin/ytd-dlp-mp4.sh`：
   
```
touch /opt/homebrew/bin/ytd-dlp-mp4.sh
```

> [!hint] 
> 建議將 Shell 檔案存放於使用者個人資料夾之下，如 /Users/user/

---
### 2. 編輯 Shell 檔案
 
 Mac 內建的 nano 和 vim 編輯器可以編輯 Shell 檔案，或者也可以使用 **TextEdit** 或ＸXcode。
 
- 使用 nano 編輯：
  
	1. 在終端中，使用 nano 打開檔案：
	   
	   ```
	   nano /opt/homebrew/bin/ytd-dlp-mp4.sh
	   ```
	   
	2. 在開啟的編輯器中輸入您的 Shell 指令。
	   
	3. 編輯完成後，按 Control + X 退出，按 Y 儲存更改，再按 Enter 確認。

- 使用 TextEdit 編輯：
  
	1. 在終端中輸入以下指令，用 TextEdit 打開檔案：
	   
	```
	open -e /opt/homebrew/bin/ytd-dlp-mp4.sh
	```
	
	2. 在 TextEdit 中輸入您的 Shell 指令，儲存並關閉檔案。
	   
---

> [!NOTE] 
> 更推薦使用 Xcode 來建立並編輯 Shell 檔案
>1. 在 Xcode 選單列點擊 → `File` → `New` → `Empty File`
>2. 將此新增檔案的副檔名改為 `.sh`
>3. 將此檔案儲存至希望存放的檔案目錄下

> [!important] 
> 1. 需建立 3 個 Shell 檔案，名稱分別為 `ytd-dlp-mp3.sh`、`ytd-dlp-mp4.sh`、`run-download.sh` 
> 2. 然後分別在 shell 檔案內貼上相同檔名的 txt 檔內的指令
> 3. shell 檔的存放位置同 yt-dlp 及 ffmpeg 為佳

---
### 3. 使 Shell 變為可執行狀態

要讓這個 Shell 檔案可以執行，您需要為它設定執行權限。在終端中輸入以下指令：

```
chmod +x /opt/homebrew/bin/ytd-dlp-mp4.sh
```


> [!important] 
> 三個檔案都要變成可執行狀態

### 4 . 執行 Shell 檔案
在終端中執行這個 Shell 檔案，可以使用以下指令：

```
/opt/homebrew/bin/ytd-dlp-mp4.sh
```

> [!hint] 
> 此時可輸入：
> ```
> ytd-dlp-mp3.sh 
> ```
> 然後輸入你要下載的連結來確認腳本是否能正常運作

 mp3 和 mp4 腳本理論上應該要能下載音檔或是影片，然後嵌入從 youtube 所獲得的封面圖以及檔案的元數據如演出者或專輯之類的資訊

---

## 使用 Automator 建立 app：

我們可以使用 Mac 內建的 Automator 來自己寫一個 app，使我們不需要每次都打開終端機輸入指令來下載影片

1. 打開 Automator，點擊 `新增文件` → `應用程式` → `選擇`
2. 接著會看到此畫面：![[截圖 2024-11-10 23.02.41.png]]
   
   在搜尋欄內搜尋 `applescript` 後將此指令拖拉至右側空白處
   ![[截圖 2024-11-10 23.04.11.png]]
   
   然後全選並清除白色區塊中的文字，貼上 `音樂下載器.txt` 檔案中的指令
   ![[截圖 2024-11-10 23.05.55.png]]
   
   即可點擊左上角的執行來執行下載任務

---

有任何問題請聯絡：
[黃弘志](mailto:gpe30201@gmail.com)

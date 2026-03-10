---
up: 
aliases: 
today:
  - "[[20241110_週日]]"
description: 
tags:
---
---
### 1. 使用 touch 命令建立 Shell 檔案

1. 打開 **終端（Terminal）**。
2. 輸入以下命令來建立新的 Shell 檔案，假設檔案路徑為 `/opt/homebrew/bin/ytd-dlp-mp4.sh`：
   
```
touch ~/opt/homebrew/bin/ytd-dlp-mp4.sh
```

> [!hint] 
> 建議將 Shell 檔案存放於使用者個人資料夾之下，如/Users/user/

---
### 2. 編輯 Shell 檔案
 
 Mac 終端機內的 nano 和 vim 編輯器可以編輯 Shell 檔案，或者也可以使用 **TextEdit** 或 Xcode、VS code。
 
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
>1. 在 Xcode 選單列點擊 → File → New → Empty File
>2. 將此新增檔案的副檔名改為 `.sh`
>3. 將此檔案儲存至希望存放的檔案目錄下

---
### 3. 使 Shell 變為可執行狀態

要讓這個 Shell 檔案可以執行，您需要為它設定執行權限。在終端中輸入以下指令：

```
chmod +x /opt/homebrew/bin/ytd-dlp-mp4.sh
```
  
### 4 . 執行 Shell 檔案

在終端中執行這個 Shell 檔案，可以使用以下指令：

```
/opt/homebrew/bin/ytd-dlp-mp4.sh
```

---

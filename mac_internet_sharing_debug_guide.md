---
up: 
aliases: 
today:
  - "[[20250404_週五]]"
description: 
tags:
---
---
# 使用 macOS 透過有線網路分享 Wi-Fi 熱點的完整指南與除錯記錄

## 📌 使用情境
你想讓你的 Mac 使用 **有線網路（Ethernet）** 上網，並透過 **Wi-Fi** 分享給其他裝置（如手機、iPad、筆電）使用。

---

## ✅ 目標設定步驟（透過 GUI 設定網際網路共享）

1. 開啟「系統設定 > 通用 > 共享」
2. 點選「網際網路共享」，設定以下選項：
   - **分享來源**：USB 有線網卡（如 `en5`）
   - **給其他裝置使用**：✅ `Wi-Fi`
3. 點選「Wi-Fi 選項」：
   - SSID：自訂熱點名稱（如 `MyMacHotspot`）
   - 頻道：建議選 `6` 或 `11`
   - 安全性：WPA2/WPA3 個人
   - 密碼：輸入 8 碼以上
4. 返回共享設定畫面 → 開啟「網際網路共享」開關
5. 成功時 Wi-Fi 圖示會變成如下圖所示：
   
   ![[mac-hotspot-share.png]]
---

## 🧪 除錯過程與使用的指令

### 🔍 查詢網路硬體介面名稱
```bash
networksetup -listallhardwareports
```

### 🔍 查看 Wi-Fi 詳細狀態（Op Mode、SSID 等）
```bash
sudo wdutil info
```

### 🔍 檢查是否成功進入 HOSTAP 模式
輸出中應包含：
- `Op Mode: HOSTAP`
- `SSID: <你設定的名稱>`
- `IPv4 Address: 192.168.2.1`

### 🔍 列出目前是否有裝置連上（NAT 網段）
```bash
arp -a
```

### 🔍 檢查是否有活躍 NAT
```bash
netstat -an | grep 192.168.2
```

---

## ❗ 常見問題與解法

### ❌ 問題 1：Wi-Fi 無法進入 Host 模式
- 解法：
  - 確保 Wi-Fi 未連線其他網路
  - 重設「網際網路共享」設定
  - 改變 Wi-Fi 頻道（如改成 6）

### ❌ 問題 2：Op Mode 為 HOSTAP，但 `SSID` 與 `IPv4` 仍為 None
- 解法：
  - 先執行：

```bash
sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.InternetSharing.plist 2>/dev/null

sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.InternetSharing.plist
```

  - **或重新關閉/開啟網際網路共享 UI 開關**

### ❌ 問題 3：看到的熱點名稱是「MacBook Pro」而不是自己設定的名稱，且不需密碼即可連線
- 原因：
  - macOS 啟動了 Apple 的「Instant Hotspot」功能（限 Apple 裝置）
- 解法：
  - 前往「系統設定 > Apple ID > iCloud > Handoff」→ 關閉 Handoff
  - 「網路 > Wi-Fi」中關閉「允許其他裝置加入熱點」
  - 重新開啟你自己設定的網際網路共享

---

## 🧼 若仍無法啟用，共有這些除錯步驟可清理設定：

```bash
sudo rm /Library/Preferences/SystemConfiguration/com.apple.nat.plist
sudo rm /Library/Preferences/SystemConfiguration/preferences.plist
sudo rm /Library/Preferences/SystemConfiguration/NetworkInterfaces.plist
sudo rm /Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist
sudo reboot
```

---

## 🧰 替代方案：使用 `create_ap` 工具手動建立熱點（不依賴 GUI）

```bash
brew install create_ap

# 執行
sudo create_ap en0 en5 MyRealHotspot mysecurepassword
```

---

## 🐞 向 Apple 回報此問題的方法

### 前往 Apple 官方回報系統：
🔗 https://feedbackassistant.apple.com

### 可使用的報告內容（摘要）：

> Internet Sharing on macOS 15.3.2 fails to start completely.  
> Wi-Fi enters HOSTAP mode but no SSID is broadcast and no NAT IP is assigned.  
> A hidden unsecured "MacBook Pro" SSID is shown to Apple devices instead.

---

## 🎉 結論

即使 macOS 的圖形介面可能無法正確反映狀態，你仍可透過 CLI 工具、觀察 `HOSTAP` 模式與 `arp -a` 檢查熱點運作，  
並利用 `create_ap` 或等待 Apple 修復 GUI 端的 Internet Sharing 問題。


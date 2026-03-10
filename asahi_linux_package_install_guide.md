# 🧰 Asahi Linux（Fedora）套件管理指令教學

這份筆記整理了 `dnf` 和 `flatpak` 的基本使用方式，適用於 Fedora KDE Plasma（如 Asahi Linux）。

---

## 🟦 dnf：Fedora 套件管理工具

### ✅ 常用指令

| 功能 | 指令 |
|------|------|
| 安裝套件 | `sudo dnf install 套件名稱` |
| 移除套件 | `sudo dnf remove 套件名稱` |
| 搜尋套件 | `dnf search 套件名稱` |
| 更新全部套件 | `sudo dnf upgrade` |
| 查詢套件資訊 | `dnf info 套件名稱` |

### 🧪 範例

```bash
sudo dnf install htop
sudo dnf remove libreoffice
dnf search vlc
```

---

## 🟩 flatpak：桌面應用推薦方式

### ✅ 第一次使用設定（只需一次）

```bash
sudo dnf install flatpak -y
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

### ✅ 常用指令

| 功能      | 指令                             |
| ------- | ------------------------------ |
| 安裝應用    | `flatpak install flathub 應用ID` |
| 執行應用    | `flatpak run 應用ID`             |
| 搜尋應用    | `flatpak search 關鍵字`           |
| 移除應用    | `flatpak uninstall 應用ID`       |
| 查看已安裝應用 | `flatpak list`                 |

### 🧪 安裝應用範例

```bash
flatpak install flathub org.telegram.desktop
flatpak run org.telegram.desktop

flatpak install flathub com.discordapp.Discord
```

---

## 📦 你想安裝的應用建議方式

| 軟體              | 安裝方式                   | 指令                                                                                     |
| --------------- | ---------------------- | -------------------------------------------------------------------------------------- |
| Obsidian        | Flatpak 或 AppImage     | `flatpak install flathub md.obsidian.Obsidian`                                         |
| LINE            | Wine 或 Web/Android 模擬器 | 無原生版本                                                                                  |
| LibreOffice     | dnf 或 flatpak          | `sudo dnf install libreoffice` 或 `flatpak install flathub org.libreoffice.LibreOffice` |
| Telegram        | Flatpak                | `flatpak install flathub org.telegram.desktop`                                         |
| Discord         | Flatpak                | `flatpak install flathub com.discordapp.Discord`                                       |
| ThinLinc Client | 官方 RPM                 | `sudo dnf install ./tl-*.rpm`                                                          |

---

## 💡 補充：哪時候該用哪個？

| 目的 | 推薦工具 | 原因 |
|------|----------|------|
| 系統工具 | `dnf` | 系統整合佳 |
| 桌面應用 | `flatpak` | 沙盒、安全性高 |
| 手動下載 `.rpm` | `dnf install xxx.rpm` | 處理依賴比 `rpm` 安全 |

---

## ✅ AppImage 使用方式（以 Obsidian 為例）

```bash
chmod +x Obsidian-*.AppImage
./Obsidian-*.AppImage
```

你可以用 KDE 的 KMenuEdit 建立桌面捷徑。

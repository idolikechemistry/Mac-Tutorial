# macOS System Tuning & Configuration
---

> [!NOTE] 
> [Chinese Version](README.md)
> 
> This document records macOS system tuning and common App configurations.
> 
> Updated at 2026-04-18

---
## Table of Contents:
- [1. System Core & Security Settings](#1-system-core--security-settings)
- [2. UI & UX Optimization](#2-ui--ux-optimization)
- [3. Development Environment Setup](#3-development-environment-setup)
- [4. Input Methods & Text Processing](#4-input-methods--text-processing)
- [5. Browsers](#5-browsers)
- [6. Mac Internet Sharing & Troubleshooting]( #6-mac-internet-Sharing--troubleshooting )

---
## 1. System Core & Security Settings

### 1.1 Allow Opening Unidentified Apps

**Function: Allow opening applications from "Anywhere".**

Enter in Terminal.app:

```bash
sudo spctl --master-disable
```

Terminal will prompt for your password. Type it and press Enter (⏎) (Note: Characters will not be visible as you type).

> [!TIP] 
> 2024-10-28: For macOS Sequoia 11.0+ changed to
> 1. First, open System Settings → Privacy & Security, and keep this window open
> 2. Open Terminal, enter the above code, type your password and press Enter (⏎)
> 3. Go back to Privacy & Security → Security → Allow applications downloaded from → The "Anywhere" option will appear in the menu (a hidden option by default)
> 4. Select "Anywhere", the system will prompt you for your password to verify

### 1.2 File Quarantine and Extended Attributes

**Check attributes:** 

```bash
xattr <path>
```

Drag and drop a file/directory into the terminal to auto-complete its path.

**Remove file quarantine extended attribute:**

```bash
sudo xattr -r -c <file_or_app_path>
```
### 1.3 Hidden Files and Folders Management

**Shortcut:** `shift (⇧) + cmd (⌘) + .` (Temporarily toggle)

**Permanently show all hidden files:**

```bash
defaults write com.apple.finder AppleShowAllFiles TRUE; killall Finder
```

To change back to the default hidden mode, simply change TRUE in the first command to FALSE.

**Hide specific folder:** 

```bash
chflags hidden <path>
```

**Unhide specific folder:**

```bash
chflags nohidden <path>
```

---
## 2. UI & UX Optimization

### 2.1 Launchpad and Dock Management

**Reset Launchpad layout / Restart Dock:**

```bash
defaults write com.apple.dock ResetLaunchPad -bool true; killall Dock
```

> [!NOTE]
> 2025-09-29: Launchpad has been removed in macOS Tahoe 26+, making this command obsolete (sadly), but it can still be used to restart the Dock when it glitches.

### 2.2 Force Quit Applications

- **Shortcut:** `cmd(⌘) + opt(⌥) + esc`

### 2.3 Screenshot and Screen Recording

#### Disable screenshot window shadows:

```bash
defaults write com.apple.screencapture disable-shadow -bool true; killall SystemUIServer
```

To restore the shadow effect, change `true` to `false`.
###### Built-in Shortcuts:

- `command (⌘) + shift (⇧) + 5`: Open interactive screenshot / screen recording tool

![](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/mac-screenshot.png)

| Action | Tool |
| :------: | :---------------------------------------------------------------------------: |
| Capture Entire Screen | ![](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/mac_screenshot-1.png) |
| Capture Window | ![](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/mac_screenshot-2.png) |
| Capture Portion of Screen | ![](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/mac_screenshot-3.png) |
| Record Entire Screen | ![](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/mac_screenshot-4.png) |
| Record Portion of Screen | ![](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/mac_screenshot-5.png) |
- Open "Settings" → "Keyboard" → "Keyboard Shortcuts..." → "Screenshots" → to view related shortcuts.

![](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/開啟Mac快速鍵設置.png)
![](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/更改Mac截圖快速鍵.png)

> [!TIP]
> For screen recording, [QuickRecorder](https://github.com/lihaoyun6/QuickRecorder?tab=readme-ov-file) is recommended.
### 2.4 Hot Corners:

![](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/mac_screen_hotspot.png)

### 2.5 Launchpad Layout Archive:

**MacOS 15 Sequoia**

![](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/Launchpad-1-20250420.png)
![](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/Launchpad-2-20250420.png)
![](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/Launchpad-3-20250420.png)

---
## 3. Development Environment Setup

### 3.1 Homebrew

#### 3.1.1 Back up Homebrew package list on the old computer

Open Terminal and enter the following command to generate a `Brewfile`:

```bash
brew bundle dump --describe --force --file="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Downloads/Brewfile"
```

This command will record all installed **Formulae (CLI packages)** and **Casks (GUI Apps)**, and save them in the iCloud Downloads folder.
`~/Library/Mobile Documents/com~apple~CloudDocs/Downloads`

> [!NOTE]
> 💡 **Path Modification Note**
> The path in the command above (`$HOME/Library/Mobile...`) saves the backup directly to iCloud Drive. If you don't use iCloud or prefer saving it locally, please replace the path with your desired local path (e.g., `~/Desktop/Brewfile`).

#### 3.1.2 Install Homebrew on the new computer

1. Open Terminal, enter the official Homebrew installation command:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

2. After installation, follow the prompt in the terminal to add the brew path to your shell (usually `/opt/homebrew/bin`).
#### 3.1.3 Restore all software at once on the new computer using Brewfile

1. Place the previously backed up `Brewfile` on the new computer (e.g. on the desktop `~/Desktop/Brewfile`)
2. Execute the following command in Terminal:

```bash
brew bundle --file=~/Desktop/Brewfile
```

- This command will automatically install all software and packages in the `Brewfile`, including command-line tools (formulae) and applications (casks).

> [!TIP]
> Export software list (Optional)
> If you just want to generate a pure list for reference, you can also:
> ```bash
> brew list > ~/Desktop/brew-formula-list.txt
> ```
> 
> ```bash
> brew list --cask > ~/Desktop/brew-cask-list.txt
> ```

### 3.2 Terminal Configuration

_(After performing each of the following operations, you need to run `source ~/.zshrc` for them to take effect)_
#### Oh-My-Zsh

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```
#### Powerlevel10k

```bash
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
```
then
```bash
nano ~/.zshrc
```
find
`ZSH_THEME="..."`
change it to
`ZSH_THEME="powerlevel10k/powerlevel10k"`
Press `Ctrl + O` → `Enter` then `Ctrl + X` to save and exit.
then
```bash
p10k configure
```
An interactive configuration wizard will launch. Follow the on-screen prompts (e.g., "**Does this look like a** diamond **(rotated square)?**") to customize your terminal appearance.
#### jetbrains-mono-nerd-font

```bash
brew install --cask font-jetbrains-mono-nerd-font
```
#### zsh-autosuggestions

```bash
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
```
#### zsh-syntax-highlighting

```bash
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```
then
```bash
nano ~/.zshrc
```
find
`plugins=(git)`
change it to
`plugins=(git zsh-autosuggestions zsh-syntax-highlighting)`
Press `Ctrl + O` → `Enter` then `Ctrl + X` to save and exit.
### 3.3 Scripts:

> [!IMPORTANT]
> **Environment Configuration (Environment Variables):**
> To be able to execute these scripts, please add the path to `~/.zshrc`:
> ```bash
> nano ~/.zshrc
> ```
> 
> ```bash
> export PATH="$HOME/Mac-set/Scripts:$PATH"
> ```
> Then press `Ctrl + O` → `Enter` → `Ctrl + X` to exit.
> 
> **Grant Permissions:**
> After cloning for the first time or adding new scripts, you must execute the following command to make them executable:
> ```bash
> chmod +x ~/Mac-set/Scripts/*.sh
> ```

| Script Name                                                             | Main Function                                                      | Dependencies                                              |
| ---------------------------------------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------- |
| [`backup_zsh.sh`](Scripts/backup_zsh.sh)                         | Backup `~/.zshrc` and `~/.p10k.zsh` to iCloud TextEdit document folder      | Built-in Bash tools                                            |
| [`dl-audio.sh`](Scripts/dl-audio.sh)                             | Download YouTube audio and choose mp3 or m4a, supports embedding chapters                 | `yt-dlp`, `ffmpeg`, `jq`                              |
| [`dl-mp4.sh`](Scripts/dl-mp4.sh)                                 | Download video/audio, process subtitles, output compatible formats (mp4/mkv)                               | `yt-dlp`, `ffmpeg`, `ffprobe`, `jq`, optional `danmaku2ass` |
| [`embed_youtube_chapters.sh`](Scripts/embed_youtube_chapters.sh) | Download chapter metadata from YouTube, and embed chapters and cover into specified video/audio files                  | `yt-dlp`, `ffmpeg`, `jq`                              |
| [`krokiet.sh`](Scripts/krokiet.sh)                               | Launch Krokiet macOS application | `macOS Terminal` / `bash`                             |
| [`lyrics-md2srt.sh`](Scripts/lyrics-md2srt.sh)                   | Convert timestamped lyrics Markdown to SRT subtitle file                             | `awk`                                                 |
| [`terminal-btop-90*26.sh`](Scripts/terminal-btop-90*26.sh)       | Open Terminal via AppleScript and run `btop` in the top right corner                  | `osascript`, `btop`, Terminal.app                     |
| [`vChewing_manager.sh`](Scripts/vChewing_manager.sh)             | Backup/restore vChewing dictionary and settings, and push/pull to GitHub                         | `git`, `defaults`, `pkill`, `bash`                    |

The scripts in this project were originally written based on the author's personal macOS (Apple Silicon) environment and usage habits. If you download or clone this project to your computer, please open the corresponding `.sh` scripts before execution and modify the following **Hardcoded Paths** according to your environment to avoid execution errors:

- `vChewing_manager.sh` : **Backup Path**
  The `BACKUP_ROOT` in the script defaults to `$HOME/my_documents/Github/my_vChewing-dic` . Be sure to change it to the local path where you want to store your backups.

- `dl-mp4.sh` : **Cookie Path**
  The default Cookie read path for Bilibili downloads is `/opt/homebrew/yt-dlp_cookie_bilibili.txt` . If you are not using an Apple Silicon Mac or the storage location is different, please change the path of `COOKIES_FILE` .

- `backup_zsh.sh` : **iCloud Dependency**
  By default, the script backs up terminal configuration files to the "TextEdit" folder in macOS iCloud ( `$HOME/Library/Mobile Documents/...` ).
  If you do not have iCloud Drive enabled or want to save locally, please modify the `DEST_DIR` variable.

- `krokiet.sh` : **App Executable Name**
  The default application name to wake up has a specific hardware compilation suffix ( `mac_krokiet_skia_vulkan_heif_avif_arm64` ).
  If you are using a standard installation version, it is recommended to change the script content directly to the generic `open -a "Krokiet"` .
  
*(Note: Some scripts contain Raycast Metadata tags like `@raycast.author` , which are purely the author's original configuration and do not affect direct execution in the terminal.)*

> [!NOTE] 
> - [`dl-mp4.sh`](Scripts/dl-mp4.sh) will automatically detect the source based on the URL and try to use browser cookies or cookies.txt.
> - [`terminal-btop-90*26.sh`](Scripts/terminal-btop-90*26.sh) requires `macOS Terminal.app` and `btop` to be available.
> - [`vChewing_manager.sh`](Scripts/vChewing_manager.sh) will read and write vChewing-related settings and backup folders under `$HOME`.

---
## 4. Input Methods & Text Processing

### 4.1 Mac Input Methods Guide
![](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/mac_keyboard.png)
- **Switch Input Method: Quickly switch between the current input method and English**
	- When using a built-in input method like Zhuyin, press the `Caps lock` key to switch between English and the current input method.
- **Switch All Input Methods:**
	- The default shortcut is to press and hold `ctrl (⌃) + Space` to cycle through all input methods in order.
	- Or press the `fn (Globe key)` to switch between all input methods.
- **Convert Half-width/Full-width Characters:**
  Zhuyin mode defaults to full-width characters, while English mode defaults to half-width.

> [!NOTE]
> 2026-02-21: Switched from the built-in Zhuyin input method to [vChewing](https://github.com/vChewing/vChewing-macOS)
> 
> For how to backup custom dictionaries and configuration files, refer to : [vChewing_manager.sh](Scripts/vChewing_manager.sh)

---
## 5. Browsers

### 5.1 Block YouTube Ads

[uBlock Origin](https://ublockorigin.com/)：Custom static rules

```js
youtube.com##+js(set, yt.config_.openPopupConfig.supportedPopups.adBlockMessageViewModel, false)
youtube.com##+js(set, Object.prototype.adBlocksFound, 0)     
youtube.com##+js(set, ytplayer.config.args.raw_player_response.adPlacements, [])
youtube.com##+js(set, Object.prototype.hasAllowedInstreamAd, true)
```

### 5.2 Firefox Browser Profile Configuration

Enter `about:config` in the Firefox address bar:

| Formula                             |        Value        |
| :---------------------------------- | :-----------------: |
| browser.gesture.pinch.in            | cmd_fullZoomReduce  |
| browser.gesture.pinch.in.shift      |  cmd_fullZoomReset  |
| browser.gesture.pinch.latched       |        true         |
| browser.gesture.pinch.out           | cmd_fullZoomEnlarge |
| browser.gesture.pinch.out.shift     |  cmd_fullZoomReset  |
| browser.tabs.closeTabByDblclick     |        true         |
| browser.tabs.closeWindowWithLastTab |        false        |
### 5.3 Enhancer for YouTube

> [!NOTE]
> 2025-10-23 at Arc

<details><summary>Click to expand Arc browser JSON settings</summary>

```json
{
  "version": "3.0.14",
  "settings": {
    "applyvideofilters": false,
    "backdropcolor": " #000000 ",
    "backdropopacity": 85,
    "blackbars": false,
    "blockautoplay": false,
    "blockhfrformats": false,
    "blockwebmformats": false,
    "boostvolume": false,
    "cinemamode": false,
    "cinemamodewideplayer": false,
    "controlbar": {
      "active": false,
      "autohide": false,
      "centered": true,
      "position": "absolute"
    },
    "controls": [
      "loop",
      "reverse-playlist",
      "speed-minus",
      "speed-plus",
      "screenshot"
    ],
    "controlsvisible": true,
    "controlspeed": true,
    "controlspeedmousebutton": false,
    "controlvolume": false,
    "controlvolumemousebutton": false,
    "convertshorts": false,
    "customcolors": {
      "--dimmer-text": " #cccccc ",
      "--hover-background": " #232323 ",
      "--main-background": " #111111 ",
      "--main-color": " #ff0033 ",
      "--main-text": " #eff0f1 ",
      "--second-background": " #181818 ",
      "--shadow": " #000000 "
    },
    "customcss": "",
    "customscript": "",
    "customtheme": false,
    "darktheme": true,
    "date": 1745134330277,
    "defaultvolume": false,
    "disableautoplay": false,
    "executescript": false,
    "expanddescription": false,
    "filter": "none",
    "griditemsperrow": {
      "channel": {
        "shorts": {
          "apply": false,
          "count": 5
        },
        "videos": {
          "apply": false,
          "count": 4
        }
      },
      "posts": {
        "apply": false,
        "count": 4
      },
      "shorts": {
        "apply": false,
        "count": 8
      },
      "videos": {
        "apply": false,
        "count": 4
      }
    },
    "hidecardsendscreens": false,
    "hidechat": false,
    "hidecomments": false,
    "hiderelated": false,
    "hideshorts": false,
    "ignoreplaylists": true,
    "ignorepopupplayer": true,
    "localecode": "zh_TW",
    "localedir": "ltr",
    "miniplayer": false,
    "miniplayerposition": "top-left",
    "miniplayersize": "480 x 270",
    "newestcomments": true,
    "overridespeeds": true,
    "pauseforegroundtab": false,
    "pausevideos": false,
    "popuplayersize": "640 x 360",
    "previousversion": "3.0.13",
    "qualityembeds": "medium",
    "qualityembedsfullscreen": "hd 1080",
    "qualityplaylists": "hd 720",
    "qualityplaylistsfullscreen": "hd 1080",
    "qualityvideos": "hd 720",
    "qualityvideosfullscreen": "hd 1080",
    "reload": true,
    "reversemousewheeldirection": false,
    "selectquality": false,
    "selectqualityfullscreenoff": false,
    "selectqualityfullscreenon": false,
    "speed": 1,
    "speedvariation": 0.25,
    "stopvideos": false,
    "theatermode": false,
    "theme": "default-dark",
    "themevariant": "dark-red.css",
    "update": 1761660999254,
    "vendorthemevariant": "youtube-deep-dark.css",
    "videofilters": {
      "blur": 0,
      "brightness": 100,
      "contrast": 100,
      "grayscale": 0,
      "inversion": 0,
      "saturation": 100,
      "sepia": 0
    },
    "volume": 50,
    "volumemultiplier": 2,
    "volumevariation": 5,
    "whatsnew": true,
    "wideplayer": false,
    "wideplayerviewport": false
  }
}
```

</details>

> [!NOTE]
> 2025-10-23 at Firefox

<details><summary>Click to expand Firefox browser JSON settings</summary>

```json
{"version":"2.0.130.1","settings":{"blur":0,"brightness":100,"contrast":100,"grayscale":0,"huerotate":0,"invert":0,"saturate":100,"sepia":0,"applyvideofilters":false,"backgroundcolor":"#000000","backgroundopacity":85,"blackbars":false,"blockautoplay":false,"blockhfrformats":false,"blockwebmformats":false,"boostvolume":false,"cinemamode":false,"cinemamodewideplayer":false,"controlbar":{"active":false,"autohide":false,"centered":true,"position":"absolute"},"controls":["loop","reverse-playlist","speed-minus","speed-plus","screenshot"],"controlsvisible":true,"controlspeed":true,"controlspeedmousebutton":false,"controlvolume":false,"controlvolumemousebutton":false,"convertshorts":false,"customcolors":{"--main-color":"#ff0033","--main-background":"#111111","--second-background":"#181818","--hover-background":"#232323","--main-text":"#eff0f1","--dimmer-text":"#cccccc","--shadow":"#000000"},"customcssrules":"","customscript":"","customtheme":false,"darktheme":true,"date":1745134330277,"defaultvolume":false,"disableautoplay":false,"executescript":false,"expanddescription":false,"filter":"none","hidecardsendscreens":false,"hidechat":false,"hidecomments":false,"hiderelated":false,"hideshorts":false,"ignoreplaylists":true,"ignorepopupplayer":true,"localecode":"zh_TW","localedir":"ltr","message":false,"miniplayer":false,"miniplayerposition":"top-left","miniplayersize":"480x270","newestcomments":true,"overridespeeds":true,"pauseforegroundtab":false,"pausevideos":false,"popuplayersize":"640x360","qualityembeds":"medium","qualityembedsfullscreen":"hd1080","qualityplaylists":"hd720","qualityplaylistsfullscreen":"hd1080","qualityvideos":"hd720","qualityvideosfullscreen":"hd1080","reload":false,"reversemousewheeldirection":false,"selectquality":false,"selectqualityfullscreenoff":false,"selectqualityfullscreenon":false,"speed":1,"speedvariation":0.25,"stopvideos":false,"theatermode":false,"theme":"default-dark","themevariant":"dark-red.css","update":1745134330277,"volume":50,"volumemultiplier":2,"volumevariation":5,"wideplayer":false,"wideplayerviewport":false}}
```

</details>

---
## 6. Mac Internet Sharing & Troubleshooting

> [!NOTE]
> Use Case
> Let Mac connect to the internet via **Ethernet** and share the connection via **Wi-Fi** to other devices (like phones, iPads, laptops). This chapter covers the GUI setup process and CLI low-level debugging records.

### 6.1 Setup via System Settings (GUI)

1. Open "System Settings" → "General" → "Sharing".
2. Click the i icon on the right side of "Internet Sharing" and configure the following options:
   * **Share your connection from:** USB Ethernet Adapter (e.g., `en5`)
   * **To computers using:** Check `Wi-Fi`
3. Click "Wi-Fi Options..." below:
   * **Network Name (SSID):** Customize your hotspot name (e.g., `MyMacHotspot`)
   * **Channel:** Recommended to choose `6` or `11`
   * **Security:** `WPA2/WPA3 Personal`
   * **Password:** Enter an 8+ character password
4. Return to the Sharing settings screen and turn on the "Internet Sharing" switch.
5. Upon successful activation, the Wi-Fi icon in the status bar will change: ![84](https://pub-b63c6b5d1dd94defbe208492cf21033f.r2.dev/mac-hotspot-share.png)

### 6.2 Terminal Debugging Commands (CLI Status Check)

If the interface shows it's on, but devices cannot connect, you can use the following commands to check the underlying status:

* **Query network hardware interface names:**
```bash
networksetup -listallhardwareports
```

* **View detailed Wi-Fi status:**
```bash
sudo wdutil NOTE
```

*(Check if the output contains `Op Mode: HOSTAP`, the correct `SSID`, and `IPv4 Address: 192.168.2.1`)*
* **List currently connected devices (NAT subnet):**
```bash
arp -a
```

* **Check for active NAT routes:**
```bash
netstat -an | grep 192.168.2
```

### 6.3 Common Issues and System-level Cleanup

**Issue 1: Op Mode is HOSTAP, but SSID and IPv4 are still None**
This indicates the macOS sharing daemon is hung. You can directly restart the core service via `launchctl`:

```bash
sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.InternetSharing.plist 2>/dev/null
```

```bash
sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.InternetSharing.plist
```

*(After execution, try turning the Internet Sharing UI switch off and on again)*

**Issue 2: The broadcasted hotspot name becomes "MacBook Pro" and does not require a password**
This is caused by interference from Apple's built-in "Instant Hotspot" feature.

* **Solution:** Go to "System Settings" → "Apple ID" → "iCloud" → "Handoff" and turn it off. Also, in "Network" → "Wi-Fi", turn off "Ask to join networks", then reconfigure sharing.

> [!IMPORTANT]
> Ultimate Cleanup (Reset all network settings)
> If none of the above methods work, you can force delete the related `.plist` configuration files and reboot (**Note: This will clear some network settings, use with caution**):
> ```bash
> sudo rm /Library/Preferences/SystemConfiguration/com.apple.nat.plist
> ```
>
> ```bash
> sudo rm /Library/Preferences/SystemConfiguration/preferences.plist
> ```
>
> ```bash
> sudo rm /Library/Preferences/SystemConfiguration/NetworkInterfaces.plist
> ```
>
> ```bash
> sudo rm /Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist
> ```
>
> ```bash
> sudo reboot
> ```

### 6.4 Alternative: Using `create_ap` (Manual Hotspot Creation via CLI)

If the built-in macOS GUI completely fails, we can use a third-party CLI tool to manually create a hotspot:

```bash
# Install create_ap
brew install create_ap
```

```bash
# Execute to create hotspot (format: sudo create_ap <shared_interface> <source_interface> <SSID> <password>)
sudo create_ap en0 en5 <HotspotName> <HotspotPassword>
```

> [!WARNING]
> Note: Reporting a Bug to Apple
> This issue occurred in macOS 15.3.2. If you encounter the `Wi-Fi enters HOSTAP mode but no SSID is broadcast...` situation, you can submit a report to Apple Feedback Assistant.
#!/usr/bin/env python3
import os
import re
import sys


def parse_time(time_str):
    """將 MM:SS.ss 轉換為總秒數"""
    parts = time_str.split(":")
    return int(parts[0]) * 60 + float(parts[1])


def format_time_srt(seconds):
    """轉換為 SRT 時間格式 HH:MM:SS,mmm"""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int(round((seconds - int(seconds)) * 1000))
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def format_time_vtt(seconds):
    """轉換為 VTT 時間格式 HH:MM:SS.mmm"""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int(round((seconds - int(seconds)) * 1000))
    return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"


def format_time_ass(seconds):
    """轉換為 ASS 時間格式 H:MM:SS.cc"""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    cs = int(round((seconds - int(seconds)) * 100))
    return f"{h}:{m:02d}:{s:02d}.{cs:02d}"


def process_lyrics(md_content):
    # 正則表達式
    # 匹配時間戳與原文：[[...#t=00:00.00|00:00]] {刻|きざ}んだ...
    time_lyric_pattern = re.compile(r"\[\[.*?#t=(\d{2}:\d{2}\.\d{2})\|.*?\]\]\s*(.*)")
    # 匹配假名：{漢字|假名} -> 漢字(假名)
    furigana_pattern = re.compile(r"\{([^|]+)\|([^}]+)\}")

    lines = md_content.split("\n")
    entries = []
    current_entry = None

    for line in lines:
        line = line.strip()
        if not line:
            continue

        time_match = time_lyric_pattern.search(line)
        if time_match:
            if current_entry:
                entries.append(current_entry)

            raw_time = time_match.group(1)
            raw_lyric = time_match.group(2)
            # 處理假名格式
            clean_lyric = furigana_pattern.sub(r"\1(\2)", raw_lyric)

            current_entry = {
                "start_sec": parse_time(raw_time),
                "lyric": clean_lyric,
                "translation": "",
            }
        elif line.startswith("*") and line.endswith("*") and current_entry:
            # 處理翻譯行
            current_entry["translation"] = line.strip("*")

    if current_entry:
        entries.append(current_entry)

    # 計算結束時間
    for i in range(len(entries)):
        if i < len(entries) - 1:
            entries[i]["end_sec"] = entries[i + 1]["start_sec"]
        else:
            entries[i]["end_sec"] = (
                entries[i]["start_sec"] + 5.0
            )  # 最後一句預設顯示 5 秒

    return entries


def generate_srt(entries, output_path):
    with open(output_path, "w", encoding="utf-8") as f:
        for i, entry in enumerate(entries, 1):
            f.write(f"{i}\n")
            f.write(
                f"{format_time_srt(entry['start_sec'])} --> {format_time_srt(entry['end_sec'])}\n"
            )
            f.write(f"{entry['lyric']}\n")
            if entry["translation"]:
                f.write(f"{entry['translation']}\n")
            f.write("\n")


def generate_vtt(entries, output_path):
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("WEBVTT\n\n")
        for i, entry in enumerate(entries, 1):
            f.write(f"{i}\n")
            f.write(
                f"{format_time_vtt(entry['start_sec'])} --> {format_time_vtt(entry['end_sec'])}\n"
            )
            f.write(f"{entry['lyric']}\n")
            if entry["translation"]:
                f.write(f"{entry['translation']}\n")
            f.write("\n")


def generate_ass(entries, output_path, title):
    ass_header = f"""[Script Info]
Title: {title}
ScriptType: v4.00+
Collisions: Normal
PlayResX: 384
PlayResY: 288
Timer: 100.0000

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(ass_header)
        for entry in entries:
            start = format_time_ass(entry["start_sec"])
            end = format_time_ass(entry["end_sec"])
            text = entry["lyric"]
            if entry["translation"]:
                text += f"\\N{entry['translation']}"  # ASS 的換行符號
            f.write(f"Dialogue: 0,{start},{end},Default,,0,0,0,,{text}\n")


def main():
    if len(sys.argv) < 3:
        print("Usage: python3 lyric_converter.py <input_md> <output_dir>")
        sys.exit(1)

    input_md = sys.argv[1]
    output_dir = sys.argv[2]

    # 取得檔名（不含副檔名）
    base_name = os.path.splitext(os.path.basename(input_md))[0]

    with open(input_md, "r", encoding="utf-8") as f:
        md_content = f.read()

    entries = process_lyrics(md_content)
    if not entries:
        print("未找到有效的歌詞時間戳。")
        sys.exit(0)

    # 產出三種格式
    generate_srt(entries, os.path.join(output_dir, f"{base_name}.srt"))
    generate_vtt(entries, os.path.join(output_dir, f"{base_name}.vtt"))
    generate_ass(entries, os.path.join(output_dir, f"{base_name}.ass"), base_name)

    print(f"Successfully converted {base_name} to SRT, VTT, and ASS.")


if __name__ == "__main__":
    main()

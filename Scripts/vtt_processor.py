import os
import re
import sys

from mutagen._file import File
from mutagen.mp4 import MP4


# ==========================================
# 模式 1：VTT 字幕時間軸處理模組
# ==========================================
def process_vtt(vtt_content, offset_seconds, start_counter):
    srt_output = []
    lrc_output = []
    ext_lrc_output = []
    current_counter = start_counter

    vtt_content = vtt_content.lstrip("\ufeff")
    blocks = re.split(r"\n\s*\n", vtt_content.strip())

    for block in blocks:
        lines = [line.strip() for line in block.split("\n") if line.strip()]
        if (
            not lines
            or lines[0].startswith("WEBVTT")
            or lines[0].startswith("Kind:")
            or lines[0].startswith("Language:")
        ):
            continue

        if "-->" not in lines[0]:
            lines.pop(0)

        if not lines:
            continue

        time_line = lines[0]
        time_match = re.match(
            r"(\d{2,}:\d{2}(?::\d{2})?\.\d{3})\s*-->\s*(\d{2,}:\d{2}(?::\d{2})?\.\d{3})",
            time_line,
        )

        if time_match:
            start_time_str = time_match.group(1)
            end_time_str = time_match.group(2)

            start_seconds = time_to_seconds(start_time_str) + offset_seconds
            end_seconds = time_to_seconds(end_time_str) + offset_seconds

            new_srt_start = seconds_to_srt_time(start_seconds)
            new_srt_end = seconds_to_srt_time(end_seconds)
            new_lrc_start = seconds_to_lrc_time(start_seconds)
            new_ext_lrc_start = seconds_to_ext_lrc_time(start_seconds)

            caption_lines = []
            for caption_line in lines[1:]:
                cleaned_line = re.sub(r"<[^>]*>", "", caption_line).strip()
                if cleaned_line:
                    caption_lines.append(cleaned_line)

            if caption_lines:
                srt_output.append(str(current_counter))
                srt_output.append(f"{new_srt_start} --> {new_srt_end}")
                srt_output.extend(caption_lines)
                srt_output.append("")
                current_counter += 1

                text_joined = " ".join(caption_lines)
                lrc_output.append(f"{new_lrc_start}{text_joined}")
                ext_lrc_output.append(f"{new_ext_lrc_start}{text_joined}")

    return (
        "\n".join(srt_output),
        "\n".join(lrc_output),
        "\n".join(ext_lrc_output),
        current_counter,
    )


def time_to_seconds(time_str):
    parts = time_str.replace(".", ":").split(":")
    if len(parts) == 3:
        return int(parts[0]) * 60 + int(parts[1]) + float(parts[2]) / 1000.0
    elif len(parts) == 4:
        return (
            int(parts[0]) * 3600
            + int(parts[1]) * 60
            + int(parts[2])
            + float(parts[3]) / 1000.0
        )
    return 0.0


def seconds_to_srt_time(total_seconds):
    hours = int(total_seconds // 3600)
    minutes = int((total_seconds % 3600) // 60)
    seconds = int(total_seconds % 60)
    milliseconds = int(round((total_seconds % 1) * 1000))
    if milliseconds >= 1000:
        milliseconds = 0
        seconds += 1
    return f"{hours:02}:{minutes:02}:{seconds:02},{milliseconds:03}"


def seconds_to_lrc_time(total_seconds):
    minutes = int(total_seconds // 60)
    seconds = int(total_seconds % 60)
    centiseconds = int(round((total_seconds % 1) * 100))
    if centiseconds >= 100:
        centiseconds = 0
        seconds += 1
    return f"[{minutes:02}:{seconds:02}.{centiseconds:02}]"


def seconds_to_ext_lrc_time(total_seconds):
    hours = int(total_seconds // 3600)
    minutes = int((total_seconds % 3600) // 60)
    seconds = int(total_seconds % 60)
    centiseconds = int(round((total_seconds % 1) * 100))
    if centiseconds >= 100:
        centiseconds = 0
        seconds += 1

    if hours > 0:
        return f"[{hours:02}:{minutes:02}:{seconds:02}.{centiseconds:02}]"
    else:
        return f"[{minutes:02}:{seconds:02}.{centiseconds:02}]"


# ==========================================
# 模式 2：Metadata 瀑布式繼承與跨格式翻譯模組
# ==========================================
def get_standard_tags(filepath):
    tags = {}
    try:
        f = File(filepath)
        if f is None:
            return tags

        # 如果是 M4A (MP4 容器)，直接讀取底層原子標籤
        if type(f).__name__ == "MP4":
            tags["title"] = f.get("\xa9nam", [None])[0]
            tags["artist"] = f.get("\xa9ART", [None])[0]
            tags["album"] = f.get("\xa9alb", [None])[0]
            tags["date"] = f.get("\xa9day", [None])[0]
            tags["genre"] = f.get("\xa9gen", [None])[0]
            tags["comment"] = f.get("\xa9cmt", [None])[0]
            tags["description"] = f.get("desc", [None])[0]
            tags["synopsis"] = f.get("syno", [None])[0]
        else:
            # 兼容 MP3/FLAC 等格式的通用標籤讀取
            try:
                ef = File(filepath, easy=True)
                if ef is not None:
                    tags["title"] = ef.get("title", [None])[0]
                    tags["artist"] = ef.get("artist", [None])[0]
                    tags["album"] = ef.get("album", [None])[0]
                    tags["date"] = ef.get("date", [None])[0]
                    tags["genre"] = ef.get("genre", [None])[0]
            except Exception:
                pass
    except Exception:
        pass

    return {k: v for k, v in tags.items() if v is not None}


def inject_metadata(target_path, ext_lrc_path, orig_files_list):
    try:
        final_tags = {}
        # 瀑布式繼承：遍歷原始檔案列表
        with open(orig_files_list, "r", encoding="utf-8") as flist:
            for line in flist:
                filepath = line.strip()
                if filepath and os.path.exists(filepath):
                    file_tags = get_standard_tags(filepath)
                    for k, v in file_tags.items():
                        if k not in final_tags:  # 最先出現的值為主
                            final_tags[k] = v

        video = MP4(target_path)

        # 寫入繼承的標籤
        if "title" in final_tags:
            video["\xa9nam"] = final_tags["title"]
        if "artist" in final_tags:
            video["\xa9ART"] = final_tags["artist"]
        if "album" in final_tags:
            video["\xa9alb"] = final_tags["album"]
        if "date" in final_tags:
            video["\xa9day"] = final_tags["date"]
        if "genre" in final_tags:
            video["\xa9gen"] = final_tags["genre"]
        if "comment" in final_tags:
            video["\xa9cmt"] = final_tags["comment"]
        if "description" in final_tags:
            video["desc"] = final_tags["description"]
        if "synopsis" in final_tags:
            video["syno"] = final_tags["synopsis"]

        # 寫入歌詞
        if os.path.exists(ext_lrc_path):
            with open(ext_lrc_path, "r", encoding="utf-8") as f_lrc:
                lyr_content = f_lrc.read()
                if lyr_content.strip():
                    video["\xa9lyr"] = lyr_content

        video.save()
        print("✅ Metadata 與歌詞標籤已無損注入 M4A")
    except Exception as e:
        print(f"⚠️ 標籤寫入失敗: {e}", file=sys.stderr)
        sys.exit(1)


# ==========================================
# 主程式入口 (CLI 路由)
# ==========================================
if __name__ == "__main__":
    # 路由 1：進入 Metadata 處理模式
    if len(sys.argv) > 1 and sys.argv[1] == "--meta":
        if len(sys.argv) != 5:
            print(
                "Usage: python3 vtt_processor.py --meta <target_m4a> <ext_lrc_path> <orig_files_list>",
                file=sys.stderr,
            )
            sys.exit(1)

        target_m4a = sys.argv[2]
        ext_lrc = sys.argv[3]
        orig_files = sys.argv[4]
        inject_metadata(target_m4a, ext_lrc, orig_files)
        sys.exit(0)

    # 路由 2：進入 VTT 字幕處理模式 (相容舊有指令格式)
    if len(sys.argv) != 7:
        print(
            "Usage: python3 vtt_processor.py <vtt_in> <offset> <start_counter> <srt_out> <lrc_out> <ext_lrc_out>",
            file=sys.stderr,
        )
        sys.exit(1)

    vtt_in, offset_str, counter_str, srt_out, lrc_out, ext_lrc_out = sys.argv[1:7]
    offset = float(offset_str)
    counter = int(counter_str)

    try:
        with open(vtt_in, "r", encoding="utf-8-sig") as f:
            vtt_content = f.read()

        srt_text, lrc_text, ext_lrc_text, new_counter = process_vtt(
            vtt_content, offset, counter
        )

        if srt_text.strip():
            with open(srt_out, "a", encoding="utf-8") as fsrt:
                fsrt.write(srt_text + "\n\n")

        if lrc_text.strip():
            with open(lrc_out, "a", encoding="utf-8") as flrc:
                flrc.write(lrc_text + "\n")

        if ext_lrc_text.strip():
            with open(ext_lrc_out, "a", encoding="utf-8") as fext:
                fext.write(ext_lrc_text + "\n")

        print(new_counter)

    except Exception as e:
        print(f"Error processing {vtt_in}: {e}", file=sys.stderr)
        print(counter)
        sys.exit(1)

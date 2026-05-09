import re
import sys


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

            # 產生三種不同規範的時間軸
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
                # SRT (原生字幕軌)
                srt_output.append(str(current_counter))
                srt_output.append(f"{new_srt_start} --> {new_srt_end}")
                srt_output.extend(caption_lines)
                srt_output.append("")
                current_counter += 1

                text_joined = " ".join(caption_lines)

                # 標準 LRC (實體備份)
                lrc_output.append(f"{new_lrc_start}{text_joined}")
                # 擴充 LRC (Mutagen 內嵌用)
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
        return int(parts[0]) * 60 + int(parts[1]) + int(parts[2]) / 1000.0
    elif len(parts) == 4:
        return (
            int(parts[0]) * 3600
            + int(parts[1]) * 60
            + int(parts[2])
            + int(parts[3]) / 1000.0
        )
    return 0


def seconds_to_srt_time(total_seconds):
    hours = int(total_seconds // 3600)
    minutes = int((total_seconds % 3600) // 60)
    seconds = int(total_seconds % 60)
    milliseconds = int((total_seconds % 1) * 1000)
    return f"{hours:02}:{minutes:02}:{seconds:02},{milliseconds:03}"


def seconds_to_lrc_time(total_seconds):
    # 標準版：允許分鐘數超過 60，相容傳統 LRC 規範
    minutes = int(total_seconds // 60)
    seconds = int(total_seconds % 60)
    centiseconds = int((total_seconds % 1) * 100)
    return f"[{minutes:02}:{seconds:02}.{centiseconds:02}]"


def seconds_to_ext_lrc_time(total_seconds):
    # 擴充版：強制解析小時，解決 Evermusic 等播放器的 60 分鐘溢位 Bug
    hours = int(total_seconds // 3600)
    minutes = int((total_seconds % 3600) // 60)
    seconds = int(total_seconds % 60)
    centiseconds = int((total_seconds % 1) * 100)

    if hours > 0:
        return f"[{hours:02}:{minutes:02}:{seconds:02}.{centiseconds:02}]"
    else:
        return f"[{minutes:02}:{seconds:02}.{centiseconds:02}]"


if __name__ == "__main__":
    if len(sys.argv) != 7:
        print(
            "Usage: python3 vtt_processor.py <vtt_in> <offset> <start_counter> <srt_out> <lrc_out> <ext_lrc_out>",
            file=sys.stderr,
        )
        sys.exit(1)

    vtt_in = sys.argv[1]
    offset = float(sys.argv[2])
    counter = int(sys.argv[3])
    srt_out = sys.argv[4]
    lrc_out = sys.argv[5]
    ext_lrc_out = sys.argv[6]

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

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


if __name__ == "__main__":
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

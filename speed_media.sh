#!/usr/bin/env bash
# ==============================================================================
# Media Speed Editor (FFmpeg Batch Processor)
#
# Clones and edits audio and video media files in the script's directory to
# playback at a specific speed factor using FFmpeg. Source tags, chapters, and
# cover art/thumbnails are preserved when the output container supports them.
#
# Configuration settings below can be adjusted directly in this file.
# ==============================================================================

set -o pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Playback speed multiplier:
# Examples:
#   0.5  = Half speed (slow motion)
#   0.75 = 75% speed
#   1.25 = 1.25x speed
#   1.5  = 1.5x speed
#   2.0  = Double speed
#   4.0  = 4x speed (timelapse / fast-forward)
#SPEED_FACTOR="1.1"
SPEED_FACTOR="${1:-1.1}"
# Match Audio Speed to Video/Media Play Speed:
# true  : Audio will be sped up or slowed down to match the new play speed,
#         maintaining synchronization with the video.
# false : Audio will NOT match the playback speed. (See AUDIO_NO_MATCH_ACTION below)
MATCH_AUDIO_SPEED="true"

# Behavior when MATCH_AUDIO_SPEED is "false":
# "mute"     : Remove/mute the audio stream completely (silent video).
# "original" : Keep original audio at 1.0x normal speed (unaltered).
#              The video plays at the modified speed while audio remains 1.0x.
AUDIO_NO_MATCH_ACTION="mute"

# Audio Pitch Correction (applied when MATCH_AUDIO_SPEED is "true"):
# true  : Preserves original vocal pitch using 'atempo' filter.
#         Speech sounds natural without squeaky chipmunk or deep monster effects.
# false : Pitch shifts proportionally with speed (classic tape / vinyl speed effect).
#         Higher pitch when fast, lower pitch when slow.
AUDIO_PITCH_CORRECTION="false"

# Output Naming & Directory:
# Suffix appended to the cloned output filename (before extension).
OUTPUT_SUFFIX="_speed_${SPEED_FACTOR}x"



# Overwrite existing output files if they already exist? (true / false)
OVERWRITE_EXISTING="true"

# Video Quality Settings (for video re-encoding):
VIDEO_CODEC="libx264"     # H.264 video codec
VIDEO_CRF="20"            # Constant Rate Factor: 0-51 (18-23 = visually lossless)
VIDEO_PRESET="medium"     # Encoding preset: ultrafast, fast, medium, slow

# Hardware Acceleration (NVIDIA NVENC/NVDEC):
# "auto" : Use NVIDIA hardware only if HWACCEL_GPU_MATCH is detected below.
# "off"  : Always use the CPU (libx264).
HWACCEL_MODE="auto"

# GPU name match (case-insensitive, partial match):
# The model must appear in `nvidia-smi --query-gpu=name`.
# Examples: "RTX 3060", "RTX 3060 Laptop GPU", "RTX 4090".
HWACCEL_GPU_MATCH="RTX 3060"

# NVENC encoder and settings used when hardware acceleration is active:
HWACCEL_VIDEO_CODEC="h264_nvenc"
HWACCEL_PRESET="p5"       # p1 (fastest) .. p7 (best quality)
HWACCEL_CQ="$VIDEO_CRF"   # NVENC constant quality: 0-51 (lower = better)

# Try NVDEC hardware decoding too. Unsupported source formats fall back to
# software decoding automatically.
HWACCEL_DECODE="true"

# Audio Quality Settings (for audio re-encoding):
AUDIO_CODEC="aac"         # Audio codec (aac for video, mp3/aac for audio)
AUDIO_BITRATE="192k"      # Audio bitrate

# Output Audio Sample Rate:
# "auto"  : Detect the source sample rate and preserve it (recommended).
#           A 48 kHz source stays 48 kHz; a 44.1 kHz source stays 44.1 kHz.
# "48000" : Force all re-encoded audio to 48 kHz (or any other numeric rate).
OUTPUT_SAMPLE_RATE="auto"

# Fallback sample rate, used only when the source rate cannot be detected.
SAMPLE_RATE_FALLBACK="48000"

# Preserve metadata (tags, chapters, cover art/thumbnail) in the output.
COPY_METADATA="true"

# Supported file extensions (case-insensitive)
VIDEO_EXTENSIONS=("mp4" "mkv" "mov" "avi" "webm" "flv" "wmv" "m4v" "ts" "3gp")
AUDIO_EXTENSIONS=("mp3" "wav" "flac" "m4a" "aac" "ogg" "wma" "opus" "aiff")

# Containers that can store attached cover art / thumbnails.
COVER_ART_EXTENSIONS=("mp3" "m4a" "mp4" "m4v" "mov" "flac")

# ==============================================================================
# SCRIPT LOGIC
# ==============================================================================

# Determine working directory (directory of script, or argument if passed)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#TARGET_DIR="${1:-$SCRIPT_DIR}"
TARGET_DIR="$SCRIPT_DIR"

# Subdirectory to place cloned/edited files:
# Leave empty ("") to place output files in the SAME directory as the originals.
# Or specify a folder name (e.g., "speed_output") to organize them separately.
OUTPUT_DIR="${2:-SCRIPT_DIR}"

# Terminal color codes
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[36m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_RED="\033[31m"
C_MAGENTA="\033[35m"

print_header() {
    echo -e "${C_CYAN}${C_BOLD}============================================================${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}             FFmpeg Media Speed Batch Editor               ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}============================================================${C_RESET}"
    echo -e " Target Directory      : ${C_YELLOW}${TARGET_DIR}${C_RESET}"
    echo -e " Speed Multiplier      : ${C_GREEN}${SPEED_FACTOR}x${C_RESET}"
    echo -e " Match Audio Speed     : ${C_GREEN}${MATCH_AUDIO_SPEED}${C_RESET}"
    if [ "$MATCH_AUDIO_SPEED" != "true" ]; then
        echo -e " Audio Action (No-Match): ${C_MAGENTA}${AUDIO_NO_MATCH_ACTION}${C_RESET}"
    else
        echo -e " Pitch Correction      : ${C_GREEN}${AUDIO_PITCH_CORRECTION}${C_RESET}"
    fi
    echo -e " Output Suffix         : ${C_YELLOW}${OUTPUT_SUFFIX}${C_RESET}"
    if [ "$OUTPUT_SAMPLE_RATE" = "auto" ]; then
        echo -e " Output Sample Rate    : ${C_GREEN}auto (preserve source)${C_RESET}"
    else
        echo -e " Output Sample Rate    : ${C_GREEN}${OUTPUT_SAMPLE_RATE} Hz (forced)${C_RESET}"
    fi
    if [ "$HWACCEL_ACTIVE" = "true" ]; then
        echo -e " Hardware Acceleration : ${C_GREEN}${HWACCEL_STATUS}${C_RESET}"
    else
        echo -e " Hardware Acceleration : ${C_YELLOW}${HWACCEL_STATUS}${C_RESET}"
    fi
    if [ -n "$OUTPUT_DIR" ]; then
        echo -e " Output Subdirectory   : ${C_YELLOW}${OUTPUT_DIR}${C_RESET}"
    else
        echo -e " Output Subdirectory   : ${C_YELLOW}(Same Directory)${C_RESET}"
    fi
    echo -e " Overwrite Existing    : ${C_YELLOW}${OVERWRITE_EXISTING}${C_RESET}"
    echo -e " Preserve Metadata     : ${C_YELLOW}${COPY_METADATA}${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}============================================================${C_RESET}\n"
}

# Verify required tools
check_prerequisites() {
    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo -e "${C_RED}[ERROR] 'ffmpeg' is not found in PATH. Please install FFmpeg or add it to PATH.${C_RESET}" >&2
        exit 1
    fi
    if ! command -v ffprobe >/dev/null 2>&1; then
        echo -e "${C_RED}[ERROR] 'ffprobe' is not found in PATH. Please install FFprobe or add it to PATH.${C_RESET}" >&2
        exit 1
    fi
    if ! command -v awk >/dev/null 2>&1; then
        echo -e "${C_RED}[ERROR] 'awk' is not found in PATH. Required for calculation.${C_RESET}" >&2
        exit 1
    fi

    # Validate SPEED_FACTOR is a positive float/number
    local is_valid_speed
    is_valid_speed=$(awk -v s="$SPEED_FACTOR" 'BEGIN { if (s > 0) print "1"; else print "0" }')
    if [ "$is_valid_speed" != "1" ]; then
        echo -e "${C_RED}[ERROR] Invalid SPEED_FACTOR '${SPEED_FACTOR}'. Must be a positive number greater than 0.${C_RESET}" >&2
        exit 1
    fi

    # Validate OUTPUT_SAMPLE_RATE: "auto" or a positive integer
    if [ "$OUTPUT_SAMPLE_RATE" != "auto" ]; then
        if ! [[ "$OUTPUT_SAMPLE_RATE" =~ ^[0-9]+$ ]] || [ "$OUTPUT_SAMPLE_RATE" -le 0 ]; then
            echo -e "${C_RED}[ERROR] Invalid OUTPUT_SAMPLE_RATE '${OUTPUT_SAMPLE_RATE}'. Use \"auto\" or a positive rate such as 48000.${C_RESET}" >&2
            exit 1
        fi
    fi
    if ! [[ "$SAMPLE_RATE_FALLBACK" =~ ^[0-9]+$ ]] || [ "$SAMPLE_RATE_FALLBACK" -le 0 ]; then
        echo -e "${C_RED}[ERROR] Invalid SAMPLE_RATE_FALLBACK '${SAMPLE_RATE_FALLBACK}'. Must be a positive integer.${C_RESET}" >&2
        exit 1
    fi
    if [ "$COPY_METADATA" != "true" ] && [ "$COPY_METADATA" != "false" ]; then
        echo -e "${C_RED}[ERROR] Invalid COPY_METADATA '${COPY_METADATA}'. Use \"true\" or \"false\".${C_RESET}" >&2
        exit 1
    fi

    # Validate hardware acceleration settings
    if [ "$HWACCEL_MODE" != "auto" ] && [ "$HWACCEL_MODE" != "off" ]; then
        echo -e "${C_RED}[ERROR] Invalid HWACCEL_MODE '${HWACCEL_MODE}'. Use \"auto\" or \"off\".${C_RESET}" >&2
        exit 1
    fi
    if [ "$HWACCEL_MODE" = "auto" ] && [ -z "$HWACCEL_GPU_MATCH" ]; then
        echo -e "${C_RED}[ERROR] HWACCEL_GPU_MATCH cannot be empty when HWACCEL_MODE is \"auto\".${C_RESET}" >&2
        exit 1
    fi
    if ! [[ "$HWACCEL_CQ" =~ ^[0-9]+$ ]] || [ "$HWACCEL_CQ" -gt 51 ]; then
        echo -e "${C_RED}[ERROR] Invalid HWACCEL_CQ '${HWACCEL_CQ}'. Must be an integer from 0 to 51.${C_RESET}" >&2
        exit 1
    fi
}

# Hardware acceleration state (set by detect_hwaccel)
HWACCEL_ACTIVE="false"
HWACCEL_DECODE_ACTIVE="false"
HWACCEL_STATUS="CPU (${VIDEO_CODEC})"

# Enable NVIDIA acceleration only when the configured GPU is present and the
# NVENC encoder can actually initialize on this machine.
detect_hwaccel() {
    HWACCEL_ACTIVE="false"
    HWACCEL_DECODE_ACTIVE="false"
    HWACCEL_STATUS="CPU (${VIDEO_CODEC})"

    if [ "$HWACCEL_MODE" = "off" ]; then
        HWACCEL_STATUS="disabled (HWACCEL_MODE=off)"
        return 0
    fi

    if ! command -v nvidia-smi >/dev/null 2>&1; then
        HWACCEL_STATUS="nvidia-smi not found; CPU (${VIDEO_CODEC})"
        return 0
    fi

    local gpu_name
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null \
        | tr -d '\r' \
        | awk -v p="$HWACCEL_GPU_MATCH" 'index(tolower($0), tolower(p)) { print $0; exit }')

    if [ -z "$gpu_name" ]; then
        HWACCEL_STATUS="'${HWACCEL_GPU_MATCH}' not found; CPU (${VIDEO_CODEC})"
        return 0
    fi

    if ! ffmpeg -hide_banner -encoders 2>/dev/null \
        | awk -v e="$HWACCEL_VIDEO_CODEC" '$2 == e { found=1 } END { exit !found }'; then
        HWACCEL_STATUS="${HWACCEL_VIDEO_CODEC} unavailable; CPU (${VIDEO_CODEC})"
        return 0
    fi

    # Verify the encoder opens successfully (GPU + driver + FFmpeg build).
    if ! ffmpeg -hide_banner -loglevel error -f lavfi \
        -i "color=c=black:s=256x256:d=0.1" -frames:v 1 \
        -c:v "$HWACCEL_VIDEO_CODEC" -f null - >/dev/null 2>&1; then
        HWACCEL_STATUS="${HWACCEL_VIDEO_CODEC} failed to initialize; CPU (${VIDEO_CODEC})"
        return 0
    fi

    HWACCEL_ACTIVE="true"
    HWACCEL_STATUS="${gpu_name} (${HWACCEL_VIDEO_CODEC})"

    if [ "$HWACCEL_DECODE" = "true" ]; then
        if ffmpeg -hide_banner -hwaccels 2>/dev/null | awk '$1 == "cuda" { found=1 } END { exit !found }'; then
            HWACCEL_DECODE_ACTIVE="true"
            HWACCEL_STATUS="${gpu_name} (NVDEC + ${HWACCEL_VIDEO_CODEC})"
        fi
    fi
}

# Helper to check if item is in array
contains_element() {
    local match="$1"
    shift
    for elem in "$@"; do
        if [ "${match,,}" = "${elem,,}" ]; then
            return 0
        fi
    done
    return 1
}

# Build FFmpeg atempo filter chain
# FFmpeg's atempo filter only supports values between 0.5 and 2.0.
# Chaining atempo filters allows any speed multiplier (e.g. 4.0 = atempo=2.0,atempo=2.0).
build_atempo_filter() {
    local speed="$1"
    awk -v s="$speed" 'BEGIN {
        chain = ""
        curr = s + 0.0
        while (curr > 2.0) {
            chain = (chain == "" ? "" : chain ",") "atempo=2.0"
            curr = curr / 2.0
        }
        while (curr < 0.5) {
            chain = (chain == "" ? "" : chain ",") "atempo=0.5"
            curr = curr / 0.5
        }
        chain = (chain == "" ? "" : chain ",") sprintf("atempo=%.4f", curr)
        print chain
    }'
}

# Probe stream indices used for mapping.
# Output: "<main_video>:<attached_pic>:<first_audio>" (empty field when absent).
probe_stream_indices() {
    local file="$1"
    ffprobe -v error -show_entries stream=index,codec_type:stream_disposition=attached_pic \
        -of csv=p=0 "$file" 2>/dev/null \
        | tr -d '\r' \
        | awk -F, '
            $2 == "video" && $3 == 1 { if (pic == "") pic = $1 }
            $2 == "video" && $3 != 1 { if (video == "") video = $1 }
            $2 == "audio" { if (audio == "") audio = $1 }
            END { printf "%s:%s:%s\n", video, pic, audio }
        '
}

# Probe sample rate for audio pitch shifting
probe_audio_sample_rate() {
    local file="$1"
    local sr
    sr=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | tr -d '\r' | awk 'NF {print $1; exit}')
    if [[ "$sr" =~ ^[0-9]+$ ]] && [ "$sr" -gt 0 ]; then
        echo "$sr"
    else
        echo "$SAMPLE_RATE_FALLBACK"
    fi
}

# Resolve the output sample rate from the detected source rate.
# "auto" preserves the source rate; a numeric value forces that rate.
resolve_output_sample_rate() {
    local source_rate="$1"
    if [ "$OUTPUT_SAMPLE_RATE" = "auto" ]; then
        echo "$source_rate"
    elif [[ "$OUTPUT_SAMPLE_RATE" =~ ^[0-9]+$ ]] && [ "$OUTPUT_SAMPLE_RATE" -gt 0 ]; then
        echo "$OUTPUT_SAMPLE_RATE"
    else
        echo -e "${C_YELLOW}[WARN] Invalid OUTPUT_SAMPLE_RATE '${OUTPUT_SAMPLE_RATE}', using ${source_rate} Hz.${C_RESET}" >&2
        echo "$source_rate"
    fi
}

# Probe container duration in seconds (empty when unavailable)
probe_duration() {
    local file="$1"
    local duration
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | tr -d '\r')
    if [[ "$duration" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk -v d="$duration" 'BEGIN { exit !(d > 0) }'; then
        echo "$duration"
    fi
}

process_file() {
    local input_path="$1"
    local filename
    filename="$(basename "$input_path")"
    local extension="${filename##*.}"
    local stem="${filename%.*}"

    # Destination directory
    local dest_dir
    if [ -n "$OUTPUT_DIR" ]; then
        dest_dir="${TARGET_DIR}/${OUTPUT_DIR}"
        mkdir -p "$dest_dir"
    else
        dest_dir="$(dirname "$input_path")"
    fi

    local output_filename="${stem}${OUTPUT_SUFFIX}.${extension}"
    local output_path="${dest_dir}/${output_filename}"

    # Prevent re-processing an existing output file or self-matching
    if [ "$input_path" = "$output_path" ]; then
        return 0
    fi

    # Check if output already exists
    if [ -f "$output_path" ] && [ "$OVERWRITE_EXISTING" != "true" ]; then
        echo -e "${C_YELLOW}[SKIP]${C_RESET} Output file already exists: ${C_YELLOW}${output_filename}${C_RESET}"
        return 2
    fi

    echo -e "${C_CYAN}[PROCESSING]${C_RESET} ${filename}"

    # Determine stream layout
    local stream_layout main_video_index cover_index audio_index
    stream_layout=$(probe_stream_indices "$input_path")
    IFS=':' read -r main_video_index cover_index audio_index <<< "$stream_layout"

    local has_video=0
    local has_audio=0
    [ -n "$main_video_index" ] && has_video=1
    [ -n "$audio_index" ] && has_audio=1

    # Treat files with audio extensions as audio-only (attached pictures are not main video)
    if contains_element "$extension" "${AUDIO_EXTENSIONS[@]}"; then
        # If the container has video that is not flagged as an attached picture,
        # still preserve it as cover art when possible.
        if [ -z "$cover_index" ] && [ -n "$main_video_index" ]; then
            cover_index="$main_video_index"
        fi
        has_video=0
    fi

    # Copy cover art only into containers that can store it.
    local has_cover=0
    if [ "$COPY_METADATA" = "true" ] && [ -n "$cover_index" ] \
        && contains_element "$extension" "${COVER_ART_EXTENSIONS[@]}"; then
        has_cover=1
    fi

    local overwrite_flag="-n"
    if [ "$OVERWRITE_EXISTING" = "true" ]; then
        overwrite_flag="-y"
    fi

    local ffmpeg_cmd=("ffmpeg" "-hide_banner" "-loglevel" "warning" "-stats" "$overwrite_flag")
    if [ "$has_video" -eq 1 ] && [ "$HWACCEL_ACTIVE" = "true" ] && [ "$HWACCEL_DECODE_ACTIVE" = "true" ]; then
        ffmpeg_cmd+=("-hwaccel" "cuda")
    fi
    ffmpeg_cmd+=("-i" "$input_path")

    if [ "$COPY_METADATA" = "true" ]; then
        ffmpeg_cmd+=("-map_metadata" "0" "-map_chapters" "0")
    else
        ffmpeg_cmd+=("-map_metadata" "-1" "-map_chapters" "-1")
    fi

    # Case 1: Video file (with or without audio)
    if [ "$has_video" -eq 1 ]; then
        ffmpeg_cmd+=("-map" "0:${main_video_index}")
        if [ "$has_audio" -eq 1 ] \
            && { [ "$MATCH_AUDIO_SPEED" = "true" ] || [ "$AUDIO_NO_MATCH_ACTION" = "original" ]; }; then
            ffmpeg_cmd+=("-map" "0:${audio_index}")
        fi
        if [ "$has_cover" -eq 1 ]; then
            ffmpeg_cmd+=("-map" "0:${cover_index}")
        fi

        # Video filter: setpts = (1/SPEED) * PTS (main video only)
        local video_pts_multiplier
        video_pts_multiplier=$(awk -v s="$SPEED_FACTOR" 'BEGIN { printf "%.6f", 1.0 / s }')

        if [ "$HWACCEL_ACTIVE" = "true" ]; then
            ffmpeg_cmd+=("-filter:v:0" "setpts=${video_pts_multiplier}*PTS" "-c:v:0" "$HWACCEL_VIDEO_CODEC" "-preset" "$HWACCEL_PRESET" "-rc" "vbr" "-cq" "$HWACCEL_CQ" "-b:v" "0")
        else
            ffmpeg_cmd+=("-filter:v:0" "setpts=${video_pts_multiplier}*PTS" "-c:v:0" "$VIDEO_CODEC" "-crf" "$VIDEO_CRF" "-preset" "$VIDEO_PRESET")
        fi

        if [ "$has_cover" -eq 1 ]; then
            ffmpeg_cmd+=("-c:v:1" "copy" "-disposition:v:1" "attached_pic")
        fi

        if [ "$has_audio" -eq 1 ]; then
            if [ "$MATCH_AUDIO_SPEED" = "true" ]; then
                local sample_rate output_rate
                sample_rate=$(probe_audio_sample_rate "$input_path")
                output_rate=$(resolve_output_sample_rate "$sample_rate")
                echo -e "${C_YELLOW}[INFO]${C_RESET} Audio sample rate: ${sample_rate} Hz -> ${output_rate} Hz"

                if [ "$AUDIO_PITCH_CORRECTION" = "true" ]; then
                    local audio_filter
                    audio_filter=$(build_atempo_filter "$SPEED_FACTOR")
                    ffmpeg_cmd+=("-filter:a" "$audio_filter" "-ar" "$output_rate" "-c:a" "$AUDIO_CODEC" "-b:a" "$AUDIO_BITRATE")
                else
                    # Pitch shifted: scale the sample rate, then resample to the output rate
                    local new_rate
                    new_rate=$(awk -v sr="$sample_rate" -v s="$SPEED_FACTOR" 'BEGIN { printf "%.0f", sr * s }')
                    ffmpeg_cmd+=("-filter:a" "asetrate=${new_rate},aresample=${output_rate}" "-ar" "$output_rate" "-c:a" "$AUDIO_CODEC" "-b:a" "$AUDIO_BITRATE")
                fi
            else
                # Audio speed does NOT match play speed
                if [ "$AUDIO_NO_MATCH_ACTION" = "mute" ]; then
                    # Strip audio track
                    ffmpeg_cmd+=("-an")
                elif [ "$AUDIO_NO_MATCH_ACTION" = "original" ]; then
                    # Keep original audio stream untouched.
                    ffmpeg_cmd+=("-c:a" "copy")
                    if [ "$has_cover" -eq 1 ]; then
                        # -shortest would stop at the single-frame cover stream.
                        # Use the scaled source duration instead.
                        local source_duration
                        source_duration=$(probe_duration "$input_path")
                        if [ -n "$source_duration" ]; then
                            local output_duration
                            output_duration=$(awk -v d="$source_duration" -v s="$SPEED_FACTOR" 'BEGIN { printf "%.6f", d / s }')
                            ffmpeg_cmd+=("-t" "$output_duration")
                        else
                            ffmpeg_cmd+=("-shortest")
                        fi
                    else
                        # Cut at whichever stream finishes first
                        ffmpeg_cmd+=("-shortest")
                    fi
                else
                    echo -e "${C_RED}[WARN] Unknown AUDIO_NO_MATCH_ACTION '${AUDIO_NO_MATCH_ACTION}', muting audio.${C_RESET}"
                    ffmpeg_cmd+=("-an")
                fi
            fi
        fi

    # Case 2: Audio-only file
    elif [ "$has_audio" -eq 1 ]; then
        if [ "$MATCH_AUDIO_SPEED" = "true" ]; then
            ffmpeg_cmd+=("-map" "0:${audio_index}")
            if [ "$has_cover" -eq 1 ]; then
                ffmpeg_cmd+=("-map" "0:${cover_index}")
            fi

            local sample_rate output_rate
            sample_rate=$(probe_audio_sample_rate "$input_path")
            output_rate=$(resolve_output_sample_rate "$sample_rate")
            echo -e "${C_YELLOW}[INFO]${C_RESET} Audio sample rate: ${sample_rate} Hz -> ${output_rate} Hz"

            if [ "$AUDIO_PITCH_CORRECTION" = "true" ]; then
                local audio_filter
                audio_filter=$(build_atempo_filter "$SPEED_FACTOR")
                ffmpeg_cmd+=("-filter:a" "$audio_filter")
            else
                local new_rate
                new_rate=$(awk -v sr="$sample_rate" -v s="$SPEED_FACTOR" 'BEGIN { printf "%.0f", sr * s }')
                ffmpeg_cmd+=("-filter:a" "asetrate=${new_rate},aresample=${output_rate}")
            fi

            # Select audio codec based on output format
            case "${extension,,}" in
                mp3) ffmpeg_cmd+=("-c:a" "libmp3lame" "-b:a" "$AUDIO_BITRATE") ;;
                wav) ffmpeg_cmd+=("-c:a" "pcm_s16le") ;;
                flac) ffmpeg_cmd+=("-c:a" "flac") ;;
                ogg) ffmpeg_cmd+=("-c:a" "libvorbis" "-b:a" "$AUDIO_BITRATE") ;;
                opus) ffmpeg_cmd+=("-c:a" "libopus" "-b:a" "$AUDIO_BITRATE") ;;
                *) ffmpeg_cmd+=("-c:a" "$AUDIO_CODEC" "-b:a" "$AUDIO_BITRATE") ;;
            esac
            ffmpeg_cmd+=("-ar" "$output_rate")
            if [ "$has_cover" -eq 1 ]; then
                ffmpeg_cmd+=("-c:v:0" "copy" "-disposition:v:0" "attached_pic")
            fi
        else
            echo -e "${C_YELLOW}[INFO]${C_RESET} MATCH_AUDIO_SPEED is false. Skipping pure audio file '${filename}'."
            return 2
        fi
    else
        echo -e "${C_YELLOW}[SKIP]${C_RESET} No supported video or audio stream found in: ${filename}"
        return 2
    fi

    # Container-specific metadata options
    if [ "$COPY_METADATA" = "true" ]; then
        case "${extension,,}" in
            mp4|m4a|m4v|mov)
                # use_metadata_tags preserves arbitrary tags, but it can drop an
                # attached cover stream in current FFmpeg builds. Prefer the
                # thumbnail when one is being copied.
                if [ "$has_cover" -eq 0 ]; then
                    ffmpeg_cmd+=("-movflags" "+use_metadata_tags")
                fi
                ;;
            mp3) ffmpeg_cmd+=("-id3v2_version" "3") ;;
        esac
    fi

    ffmpeg_cmd+=("$output_path")

    # Execute FFmpeg command
    if "${ffmpeg_cmd[@]}"; then
        echo -e "${C_GREEN}[SUCCESS]${C_RESET} -> ${output_filename}\n"
        return 0
    else
        echo -e "${C_RED}[FAILED]${C_RESET} Could not process: ${filename}\n"
        # Remove partial output if failed
        [ -f "$output_path" ] && rm -f "$output_path"
        return 1
    fi
}

main() {
    check_prerequisites
    detect_hwaccel
    print_header

    if [ ! -d "$TARGET_DIR" ]; then
        echo -e "${C_RED}[ERROR] Target directory does not exist: ${TARGET_DIR}${C_RESET}" >&2
        exit 1
    fi

    # Collect matching media files
    local files_to_process=()
    shopt -s nullglob nocaseglob

    for file in "$TARGET_DIR"/*; do
        # Ignore subdirectories and the script itself
        if [ -d "$file" ]; then
            continue
        fi
        local fname
        fname="$(basename "$file")"
        local ext="${fname##*.}"

        # Ignore script files
        if [ "${ext,,}" = "sh" ] || [ "${ext,,}" = "bash" ]; then
            continue
        fi

        # Ignore files that already contain the configured output suffix to prevent loops
        if [[ "$fname" == *"${OUTPUT_SUFFIX}."* ]]; then
            continue
        fi

        # Check against video and audio extensions
        if contains_element "$ext" "${VIDEO_EXTENSIONS[@]}" || contains_element "$ext" "${AUDIO_EXTENSIONS[@]}"; then
            files_to_process+=("$file")
        fi
    done

    shopt -u nullglob nocaseglob

    local total_files="${#files_to_process[@]}"

    if [ "$total_files" -eq 0 ]; then
        echo -e "${C_YELLOW}No matching media files found in: ${TARGET_DIR}${C_RESET}"
        echo -e "Supported extensions:"
        echo -e "  Video: ${VIDEO_EXTENSIONS[*]}"
        echo -e "  Audio: ${AUDIO_EXTENSIONS[*]}"
        exit 0
    fi

    echo -e "Found ${C_BOLD}${total_files}${C_RESET} media file(s) to process.\n"

    local count_success=0
    local count_skipped=0
    local count_failed=0

    for file in "${files_to_process[@]}"; do
        process_file "$file"
        res=$?
        if [ $res -eq 0 ]; then
            ((count_success++))
        elif [ $res -eq 2 ]; then
            ((count_skipped++))
        else
            ((count_failed++))
        fi
    done

    echo -e "${C_CYAN}${C_BOLD}============================================================${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                       Summary                              ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}============================================================${C_RESET}"
    echo -e " Total Files Found : ${total_files}"
    echo -e " Succeeded         : ${C_GREEN}${count_success}${C_RESET}"
    echo -e " Skipped           : ${C_YELLOW}${count_skipped}${C_RESET}"
    echo -e " Failed            : ${C_RED}${count_failed}${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}============================================================${C_RESET}\n"
}

main "$@"

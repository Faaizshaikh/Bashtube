#!/usr/bin/env bash
# bashtube.sh - search & play YouTube videos from terminal
# Requirements: bash (4+), curl, jq, mpv (or vlc), optionally yt-dlp for best compatibility
# Usage: ./bashtube.sh "search query"  OR  ./bashtube.sh -n 5 "search query"

set -euo pipefail
IFS=$'\n\t'

# ----- CONFIG -----
# Supply API key in one of these ways (priority order):
# 1) Environment variable: YT_API_KEY
# 2) Config file: ~/.bashtube.conf with line YT_API_KEY="your_key_here"
# 3) Prompt the user to paste the key at first run
DEFAULT_MAX_RESULTS=10
API_KEY=""
CONFIG_FILE="$HOME/.bashtube.conf"

# ----- HELP -----
usage() {
  cat <<EOF
BashTube: Search & play YouTube from terminal

Usage:
  $0 [options] "search terms"

Options:
  -n NUM     Number of results to show (default: $DEFAULT_MAX_RESULTS)
  -h         Show this help and exit
  -q         Quiet: skip menu and play first result

Examples:
  $0 "lofi beats"
  $0 -n 5 "programming tutorials"

EOF
}

# ----- UTILITIES -----
error() { echo "[ERROR] $*" >&2; exit 1; }
warn()  { echo "[WARN] $*" >&2; }
info()  { echo "[INFO] $*"; }

# Convert ISO 8601 duration (PT#H#M#S) to human readable (H:MM:SS or M:SS)
iso8601_to_hms() {
  local dur="$1"
  local hours=0 minutes=0 seconds=0
  dur=${dur#PT}
  if [[ $dur =~ ([0-9]+)H ]]; then hours=${BASH_REMATCH[1]}; fi
  if [[ $dur =~ ([0-9]+)M ]]; then minutes=${BASH_REMATCH[1]}; fi
  if [[ $dur =~ ([0-9]+)S ]]; then seconds=${BASH_REMATCH[1]}; fi
  if (( hours>0 )); then
    printf "%d:%02d:%02d" "$hours" "$minutes" "$seconds"
  else
    printf "%d:%02d" "$minutes" "$seconds"
  fi
}

# Load API key
load_api_key() {
  if [[ -n "${YT_API_KEY-}" ]]; then
    API_KEY="$YT_API_KEY"
    return
  fi
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE" || true
    if [[ -n "${YT_API_KEY-}" ]]; then
      API_KEY="$YT_API_KEY"
      return
    fi
  fi
  # fallback: prompt once
  read -r -p "Enter your YouTube Data API key (will be saved to $CONFIG_FILE)? [y/N] " savekey
  if [[ "$savekey" =~ ^[Yy]$ ]]; then
    read -r -p "Paste API key: " keyval
    echo "YT_API_KEY=\"$keyval\"" > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    API_KEY="$keyval"
  else
    read -r -p "Paste API key to use for this run (won't be saved): " keyval
    API_KEY="$keyval"
  fi
}

# Check dependencies
check_deps() {
  local missing=()
  for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if ! command -v mpv &>/dev/null && ! command -v vlc &>/dev/null; then
    missing+=("mpv or vlc")
  fi
  if ((${#missing[@]})); then
    error "Missing dependencies: ${missing[*]}. Install them (e.g. sudo apt install mpv jq curl) and try again."
  fi
}

# Perform the search via YouTube Data API
# Arguments: query, maxResults
youtube_search() {
  local query="$1"
  local max="$2"
  local qenc
  qenc=$(printf "%s" "$query" | jq -s -R -r @uri)
  local url="https://www.googleapis.com/youtube/v3/search?part=snippet&maxResults=${max}&q=${qenc}&type=video&key=${API_KEY}"
  curl -sSf --retry 2 --retry-delay 1 "$url"
}

# Fetch video details (duration) using videos endpoint
# Arguments: comma-separated list of ids
youtube_videos_details() {
  local ids="$1"
  local url="https://www.googleapis.com/youtube/v3/videos?part=contentDetails&id=${ids}&key=${API_KEY}"
  curl -sSf --retry 2 --retry-delay 1 "$url"
}

# Play video using mpv or vlc, prefer mpv
play_video() {
  local vid="$1"
  local url="https://www.youtube.com/watch?v=${vid}"
  if command -v mpv &>/dev/null; then
    # if yt-dlp present, mpv will use it for best results
    mpv --no-terminal "$url"
  else
    # fallback to vlc
    cvlc --play-and-exit "$url"
  fi
}

# ----- MAIN -----

# Parse options
MAX_RESULTS=$DEFAULT_MAX_RESULTS
QUIET=0
while getopts ":n:qh" opt; do
  case $opt in
    n) MAX_RESULTS="$OPTARG" ;;
    q) QUIET=1 ;;
    h) usage; exit 0 ;;
    :) error "-$OPTARG requires an argument" ;;
    \?) error "Unknown option: -$OPTARG" ;;
  esac
done
shift $((OPTIND-1))

if (($# == 0)); then
  usage
  exit 1
fi

SEARCH_TERM="$*"

check_deps
load_api_key

# Query YouTube
info "Searching YouTube for: $SEARCH_TERM (max $MAX_RESULTS results)"
json=$(youtube_search "$SEARCH_TERM" "$MAX_RESULTS") || error "Search failed. Check API key and network."

# Extract IDs and titles
mapfile -t ids < <(printf "%s" "$json" | jq -r '.items[] | .id.videoId')
mapfile -t titles < <(printf "%s" "$json" | jq -r '.items[] | .snippet.title')
mapfile -t channels < <(printf "%s" "$json" | jq -r '.items[] | .snippet.channelTitle')

if ((${#ids[@]} == 0)); then
  error "No results found."
fi

# Fetch durations
idcsv=$(IFS=, ; echo "${ids[*]}")
details_json=$(youtube_videos_details "$idcsv")
mapfile -t durations_raw < <(printf "%s" "$details_json" | jq -r '.items[] | .contentDetails.duration')

# Convert durations and display menu
printf "\nResults:\n"
for i in "${!ids[@]}"; do
  idx=$((i+1))
  dur_human=$(iso8601_to_hms "${durations_raw[i]:-PT0S}")
  printf "%2d) %s  —  %s (%s)\n" "$idx" "${titles[i]}" "${channels[i]}" "$dur_human"
done

choice=1
if [[ "$QUIET" -eq 1 ]]; then
  choice=1
else
  printf "\nEnter number to play (1-%d), or q to quit: " ${#ids[@]}
  read -r sel
  if [[ "$sel" =~ ^[Qq]$ ]]; then
    echo "Goodbye."; exit 0
  fi
  if ! [[ "$sel" =~ ^[0-9]+$ ]]; then
    error "Invalid selection."
  fi
  if (( sel < 1 || sel > ${#ids[@]} )); then
    error "Selection out of range."
  fi
  choice=$sel
fi

VIDEO_ID=${ids[$((choice-1))]}
info "Playing: ${titles[$((choice-1))]} — https://youtu.be/${VIDEO_ID}"
play_video "$VIDEO_ID"

exit 0

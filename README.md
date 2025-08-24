# BashTube – YouTube in Terminal & GUI

BashTube is a **Linux-based Bash script** that lets you **search and play YouTube videos directly from your terminal or a simple GUI**. It uses the **YouTube Data API** with `mpv` or `vlc` to provide a minimal, fast, and distraction-free YouTube experience.

---

## Features

- Search YouTube videos from terminal or GUI.
- Display results with **titles, channels, and durations**.
- Play videos directly in `mpv` or `vlc`.
- Quiet mode: skip selection menu and play first result.
- Configurable number of search results.
- GUI mode using **Zenity**.

---

## Requirements

- Bash **4+**
- `curl`
- `jq`
- `mpv` (preferred) or `vlc`
- YouTube Data API key
- Optional: `yt-dlp` for best compatibility
- Optional GUI: `zenity`

Install dependencies on Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y curl jq mpv vlc zenity

#!/usr/bin/env bash
set -euo pipefail

# Check if xrandr is available
if ! command -v xrandr &>/dev/null; then
  echo "xrandr not found. Using standard DPI." >&2
  exit 1
fi

# Get count of all active monitors
total_monitors=$(xrandr --listactivemonitors | head -n1 | awk '{print $2}')
if [ "$total_monitors" -eq 0 ]; then
  echo "No active monitors detected. Using standard DPI." >&2
  exit 1
fi

# Check each monitor - exit early if any non-HiDPI monitor is found
while read -r line; do
  # Skip the first line which shows total count
  if [[ $line =~ ^[[:space:]]*[0-9]+: ]]; then
    # Extract resolution part (e.g., "3840/1016x2160/571")
    resolution=$(echo "$line" | awk '{print $3}' | cut -d'+' -f1)

    # Extract height
    height=$(echo "$resolution" | awk -F'[x/]' '{print $3}')

    # Check if height is 2160 or greater
    if [ -n "$height" ] && [ "$height" -ge 2160 ]; then
      echo "HiDPI monitor detected: $line" >&2
    else
      echo "Standard DPI monitor detected: $line" >&2
      exit 1 # Early exit - found a standard DPI monitor
    fi
  fi
done < <(xrandr --listactivemonitors)

# If we get here, all monitors are HiDPI
echo "All monitors are HiDPI" >&2
exit 0

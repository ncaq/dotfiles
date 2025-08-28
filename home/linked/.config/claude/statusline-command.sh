#!/usr/bin/env bash

# Claude Code Status Line Command
# Based on Starship configuration from ~/.config/starship.toml

# Read JSON input from stdin
input=$(cat)

# Extract information from JSON
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
model_name=$(echo "$input" | jq -r '.model.display_name')
output_style=$(echo "$input" | jq -r '.output_style.name')

# Time in ISO format (matching starship config)
time_str=$(date "+%Y-%m-%dT%H:%M:%S")

# Username and hostname
user=$(whoami)
hostname=$(hostname -s)

# Create status line matching Starship format
printf '[%s] %s@%s:%s | %s (%s)\n' "$time_str" "$user" "$hostname" "$current_dir" "$model_name" "$output_style"

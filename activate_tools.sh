#!/bin/bash

BIN_DIR="$HOME/dev/cli-tools/bin"
TARGET_DIR="/usr/local/bin"

for script in "$BIN_DIR"/*; do
    [ -f "$script" ] || continue  # Skip if not a regular file
    script_name=$(basename "$script")
    target_path="$TARGET_DIR/$script_name"

    echo "Linking $script → $target_path"
    ln -sf "$script" "$target_path"
    chmod +x "$script"
done

echo "All tools activated."

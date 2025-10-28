#!/usr/bin/env python3
"""
Generate Jezza texture atlas from animation frames
Organizes animations into rows for shader-based animation
"""

import os
import subprocess
from pathlib import Path

# Animation mappings (matches AnimType enum in jezza.gd)
# Format: (folder_name, row_index, frame_count)
ANIMATIONS = [
    ("raptor-idle", 0, 2),           # IDLE = 0, 248px = 2 frames
    ("raptor-walk", 1, 6),           # WALK = 1, 768px = 6 frames
    ("raptor-run", 2, 6),            # RUN = 2, 768px = 6 frames
    ("raptor-bite", 3, 10),          # BITE = 3, 1280px = 10 frames
    ("raptor-pounce", 4, 1),         # POUNCE = 4, 128px = 1 frame
    ("raptor-ready-pounce", 5, 2),   # POUNCE_READY = 5, 256px = 2 frames
    ("raptor-pounce-end", 6, 1),     # POUNCE_END = 6, 128px = 1 frame
    ("raptor-pounce-latched", 7, 1), # POUNCE_LATCHED = 7, 128px = 1 frame
    ("raptor-pounced-attack", 8, 8), # POUNCED_ATTACK = 8, 1024px = 8 frames
    ("raptor-roar", 9, 6),           # ROAR = 9, 768px = 6 frames
    ("raptor-scanning", 10, 18),     # SCANNING = 10, 2304px = 18 frames
    ("raptor-on-hit", 11, 1),        # ON_HIT = 11, 128px = 1 frame
    ("raptor-dead", 12, 6),          # DEAD = 12, 768px = 6 frames
    ("raptor-jump", 13, 1),          # JUMP = 13, 128px = 1 frame
    ("raptor-falling", 14, 1),       # FALLING = 14, 128px = 1 frame
]

FRAME_WIDTH = 128  # Width of each frame in atlas
FRAME_HEIGHT = 64  # Height of each frame in atlas
MAX_FRAMES_PER_ROW = 18  # Maximum frames for any animation (scanning has 36)

def create_atlas():
    """Create texture atlas using ImageMagick"""

    script_dir = Path(__file__).parent
    atlas_path = script_dir / "jezza_atlas.png"

    print("Creating Jezza texture atlas...")

    # Calculate atlas dimensions
    atlas_width = FRAME_WIDTH * MAX_FRAMES_PER_ROW
    atlas_height = FRAME_HEIGHT * len(ANIMATIONS)

    print(f"Atlas size: {atlas_width}x{atlas_height}")

    # Get sheets directory
    sheets_dir = script_dir / "sheets"

    # Create RGBA background by using one of the sheets as a template
    # This ensures we have proper color channels from the start
    first_anim_name = ANIMATIONS[0][0]  # Get just the name from tuple
    first_sheet = sheets_dir / f"{first_anim_name}.png"
    cmd = [
        "convert",
        str(first_sheet),
        "-alpha", "set",
        "-background", "none",
        "-type", "TrueColorAlpha",
        "-extent", f"{atlas_width}x{atlas_height}",
        "-colorspace", "sRGB",
        str(atlas_path)
    ]
    subprocess.run(cmd, check=True)

    # Clear it to transparent
    cmd = [
        "convert",
        str(atlas_path),
        "-fill", "none",
        "-draw", f"rectangle 0,0 {atlas_width},{atlas_height}",
        str(atlas_path)
    ]
    subprocess.run(cmd, check=True)
    print(f"Created blank atlas: {atlas_path}")

    # Composite each animation row from pre-made sheets
    for anim_folder, row_index, frame_count in ANIMATIONS:
        sheet_path = sheets_dir / f"{anim_folder}.png"

        if not sheet_path.exists():
            print(f"Warning: Sheet not found: {sheet_path}")
            continue

        # Get sheet dimensions
        result = subprocess.run(
            ["identify", "-format", "%w %h", str(sheet_path)],
            capture_output=True,
            text=True,
            check=True
        )
        sheet_width, sheet_height = map(int, result.stdout.strip().split())

        # Calculate frame width in the source sheet
        frame_width_in_sheet = sheet_width / frame_count

        print(f"Processing {anim_folder} sheet: {sheet_width}x{sheet_height}, {frame_count} frames @ {frame_width_in_sheet:.0f}px each")

        y_offset = row_index * FRAME_HEIGHT
        print(f"  Placing in atlas at row {row_index}, y_offset={y_offset}")

        # Extract and composite each frame individually
        for frame_idx in range(min(frame_count, MAX_FRAMES_PER_ROW)):
            x_in_sheet = int(frame_idx * frame_width_in_sheet)
            x_in_atlas = frame_idx * FRAME_WIDTH

            if frame_idx == 0:
                print(f"  Frame 0: cropping {int(frame_width_in_sheet)}x{sheet_height} from sheet, placing at atlas ({x_in_atlas}, {y_offset})")

            # Extract frame from sheet, resize to 128x64 maintaining aspect ratio
            cmd = [
                "convert",
                str(atlas_path),
                "(",
                str(sheet_path),
                "-crop", f"{int(frame_width_in_sheet)}x{sheet_height}+{x_in_sheet}+0",
                "+repage",
                "-resize", f"{FRAME_WIDTH}x{FRAME_HEIGHT}",  # Resize to fit 128x64, maintain aspect
                "-background", "none",
                "-gravity", "center",
                "-extent", f"{FRAME_WIDTH}x{FRAME_HEIGHT}",  # Center in 128x64 frame
                "-type", "TrueColorAlpha",
                ")",
                "-geometry", f"+{x_in_atlas}+{y_offset}",
                "-composite",
                str(atlas_path)
            ]
            result = subprocess.run(cmd, check=True, capture_output=True, text=True)
            if result.returncode != 0:
                print(f"  ERROR on frame {frame_idx}: {result.stderr}")

    print(f"\n✓ Atlas created successfully: {atlas_path}")
    print(f"  Size: {atlas_width}x{atlas_height}")
    print(f"  Frame size: {FRAME_WIDTH}x{FRAME_HEIGHT}")
    print(f"  Animations: {len(ANIMATIONS)} rows")
    print(f"  Max frames per row: {MAX_FRAMES_PER_ROW}")

if __name__ == "__main__":
    create_atlas()

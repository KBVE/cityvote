#!/usr/bin/env python3
"""
Fire Worm Sprite Atlas Generator

Generates a multi-row sprite atlas from Fire Worm animation sheets.
Fire Worm is a 90x90 pixels animated character with 5 animation sheets.

Animation Sheets:
  - Idle: 9 frames
  - Walk: 9 frames
  - Attack: 16 frames
  - Get Hit: 3 frames
  - Death: 8 frames

Atlas Layout (5 rows × 16 columns max):
  Row 0: Idle (9 frames)
  Row 1: Walk (9 frames)
  Row 2: Attack (16 frames)
  Row 3: Get Hit (3 frames)
  Row 4: Death (8 frames)

Frame Size: 90x90 pixels per frame
Atlas Size: 1440x450 pixels (16 columns × 5 rows @ 90x90 each)

Usage:
    python create_fireworm_atlas.py

Input:
    - Idle.png (810x90, 9 frames @ 90x90)
    - Walk.png (810x90, 9 frames @ 90x90)
    - Attack.png (1440x90, 16 frames @ 90x90)
    - Get Hit.png (270x90, 3 frames @ 90x90)
    - Death.png (720x90, 8 frames @ 90x90)

Output:
    - fireworm_atlas.png: Combined sprite atlas (1440x450)
    - fireworm_atlas_metadata.json: Animation metadata
"""

import os
from PIL import Image
import json

# Configuration
FRAME_WIDTH = 90   # Width of each frame (actual size from sprites)
FRAME_HEIGHT = 90  # Height of each frame (actual size from sprites)
ASSETS_DIR = "."   # Assets are in the current directory
OUTPUT_ATLAS = "fireworm_atlas.png"
OUTPUT_METADATA = "fireworm_atlas_metadata.json"

# Animation definitions (row, source_file, frame_count)
ANIMATIONS = [
    {
        "name": "idle",
        "source": "Idle.png",
        "frames": 9,
        "row": 0,
        "fps": 8
    },
    {
        "name": "walk",
        "source": "Walk.png",
        "frames": 9,
        "row": 1,
        "fps": 10
    },
    {
        "name": "attack",
        "source": "Attack.png",
        "frames": 16,
        "row": 2,
        "fps": 12
    },
    {
        "name": "take_hit",
        "source": "Get Hit.png",
        "frames": 3,
        "row": 3,
        "fps": 8
    },
    {
        "name": "death",
        "source": "Death.png",
        "frames": 8,
        "row": 4,
        "fps": 10
    }
]


def extract_frame(sprite_sheet, frame_index):
    """Extract a single frame from horizontal sprite sheet"""
    x = frame_index * FRAME_WIDTH
    y = 0
    return sprite_sheet.crop((x, y, x + FRAME_WIDTH, y + FRAME_HEIGHT))


def generate_atlas():
    """Generate multi-row sprite atlas from Fire Worm animation sheets"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    assets_path = os.path.join(script_dir, ASSETS_DIR)

    if not os.path.exists(assets_path):
        print(f"Error: Assets directory not found: {assets_path}")
        return False

    # Calculate atlas dimensions
    max_frames = max(anim["frames"] for anim in ANIMATIONS)
    atlas_width = max_frames * FRAME_WIDTH  # 16 * 51 = 816
    atlas_height = len(ANIMATIONS) * FRAME_HEIGHT  # 5 * 41 = 205

    print(f"Atlas dimensions: {atlas_width}x{atlas_height} ({len(ANIMATIONS)} rows, max {max_frames} frames)")
    print(f"Frame size: {FRAME_WIDTH}x{FRAME_HEIGHT}")

    # Create atlas with transparency
    atlas = Image.new("RGBA", (atlas_width, atlas_height), (0, 0, 0, 0))

    # Metadata
    metadata = {
        "frame_width": FRAME_WIDTH,
        "frame_height": FRAME_HEIGHT,
        "atlas_width": atlas_width,
        "atlas_height": atlas_height,
        "rows": len(ANIMATIONS),
        "max_frames": max_frames,
        "animations": []
    }

    # Process each animation
    for anim_data in ANIMATIONS:
        name = anim_data["name"]
        source = anim_data["source"]
        frames = anim_data["frames"]
        row = anim_data["row"]
        fps = anim_data["fps"]

        filepath = os.path.join(assets_path, source)

        if not os.path.exists(filepath):
            print(f"Warning: Animation sheet not found: {filepath}")
            continue

        print(f"\nProcessing: {name} (row {row}, {frames} frames @ {fps} fps)")

        # Load sprite sheet
        sprite_sheet = Image.open(filepath).convert("RGBA")
        expected_width = frames * FRAME_WIDTH

        if sprite_sheet.size != (expected_width, FRAME_HEIGHT):
            print(f"  Warning: Expected size ({expected_width}, {FRAME_HEIGHT}), got {sprite_sheet.size}")

        # Extract and paste each frame
        for frame_idx in range(frames):
            frame = extract_frame(sprite_sheet, frame_idx)

            x_pos = frame_idx * FRAME_WIDTH
            y_pos = row * FRAME_HEIGHT

            atlas.paste(frame, (x_pos, y_pos), frame)
            print(f"  Frame {frame_idx}: pasted at ({x_pos}, {y_pos})")

        # Store metadata
        anim_metadata = {
            "name": name,
            "row": row,
            "frames": frames,
            "fps": fps,
            "frame_start": 0,
            "frame_end": frames - 1
        }
        metadata["animations"].append(anim_metadata)

    # Save atlas
    output_atlas_path = os.path.join(script_dir, OUTPUT_ATLAS)
    atlas.save(output_atlas_path, "PNG")
    print(f"\n✓ Atlas saved: {output_atlas_path}")
    print(f"  Size: {atlas_width}x{atlas_height}")

    # Save metadata
    output_metadata_path = os.path.join(script_dir, OUTPUT_METADATA)
    with open(output_metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"✓ Metadata saved: {output_metadata_path}")

    # Print animation info
    print("\n📊 Animation Layout:")
    for anim in metadata["animations"]:
        print(f"  Row {anim['row']}: {anim['name']} ({anim['frames']} frames @ {anim['fps']} fps)")

    print("\n🎨 UV Coordinates (V is constant per row):")
    for anim in metadata["animations"]:
        v_min = (anim['row'] * FRAME_HEIGHT) / atlas_height
        v_max = ((anim['row'] + 1) * FRAME_HEIGHT) / atlas_height
        print(f"  {anim['name']} (row {anim['row']}): V=[{v_min:.4f}, {v_max:.4f}]")

    return True


if __name__ == "__main__":
    print("🔥 Fire Worm Sprite Atlas Generator")
    print("=" * 50)

    success = generate_atlas()

    if success:
        print("\n✅ Atlas generation complete!")
    else:
        print("\n❌ Atlas generation failed!")
        exit(1)

#!/usr/bin/env python3
"""
Sprite Atlas Generator for Martial Hero

This script combines all individual animation PNG files into a single sprite atlas
and generates accompanying JSON metadata for easy use in Godot.

Animation Frame Counts:
- Idle - 8 frames
- Run - 8 frames
- Jump - 4 frames
- Fall - 4 frames
- Attack1 - 6 frames
- Attack2 - 6 frames
- Take Hit - 4 frames
- Death - 6 frames

Total: 46 frames

Output:
- martialhero_atlas.png: Sprite atlas image (organized in rows by animation)
- martialhero_atlas.json: Metadata with frame positions and animation data

Usage:
    python3 generate_sprite_atlas.py
"""

import json
from pathlib import Path
from PIL import Image

# Animation configuration (order matters for atlas layout)
ANIMATIONS = [
    {"name": "Idle", "filename": "Idle.png", "frames": 8},
    {"name": "Run", "filename": "Run.png", "frames": 8},
    {"name": "Jump", "filename": "Jump.png", "frames": 4},
    {"name": "Fall", "filename": "Fall.png", "frames": 4},
    {"name": "Attack1", "filename": "Attack1.png", "frames": 6},
    {"name": "Attack2", "filename": "Attack2.png", "frames": 6},
    {"name": "Take Hit", "filename": "Take Hit.png", "frames": 4},
    {"name": "Death", "filename": "Death.png", "frames": 6},
]

# Frame dimensions (all sprites are 200x200 per frame)
FRAME_WIDTH = 200
FRAME_HEIGHT = 200

def generate_sprite_atlas():
    """Generate sprite atlas and metadata JSON."""
    script_dir = Path(__file__).parent

    # Calculate atlas dimensions
    # We'll arrange animations in rows: each animation gets its own row
    max_frames_per_row = max(anim["frames"] for anim in ANIMATIONS)
    atlas_width = max_frames_per_row * FRAME_WIDTH
    atlas_height = len(ANIMATIONS) * FRAME_HEIGHT

    print(f"Creating atlas: {atlas_width}x{atlas_height}")
    print(f"Max frames per row: {max_frames_per_row}")

    # Create blank atlas image (RGBA for transparency)
    atlas = Image.new('RGBA', (atlas_width, atlas_height), (0, 0, 0, 0))

    # Metadata for JSON output
    metadata = {
        "atlas_width": atlas_width,
        "atlas_height": atlas_height,
        "frame_width": FRAME_WIDTH,
        "frame_height": FRAME_HEIGHT,
        "animations": []
    }

    # Process each animation
    for row_index, anim in enumerate(ANIMATIONS):
        anim_name = anim["name"]
        filename = anim["filename"]
        frame_count = anim["frames"]

        print(f"Processing {anim_name}: {filename} ({frame_count} frames)")

        # Load source image
        source_path = script_dir / filename
        if not source_path.exists():
            print(f"  WARNING: {filename} not found, skipping...")
            continue

        source_img = Image.open(source_path)
        source_width, source_height = source_img.size

        # Verify source image dimensions
        expected_width = frame_count * FRAME_WIDTH
        if source_width != expected_width or source_height != FRAME_HEIGHT:
            print(f"  WARNING: Expected {expected_width}x{FRAME_HEIGHT}, got {source_width}x{source_height}")

        # Extract and paste each frame
        frames_metadata = []
        for frame_index in range(frame_count):
            # Source position (horizontal strip)
            src_x = frame_index * FRAME_WIDTH
            src_y = 0

            # Destination position in atlas
            dest_x = frame_index * FRAME_WIDTH
            dest_y = row_index * FRAME_HEIGHT

            # Extract frame from source
            frame_box = (src_x, src_y, src_x + FRAME_WIDTH, src_y + FRAME_HEIGHT)
            frame = source_img.crop(frame_box)

            # Paste into atlas
            atlas.paste(frame, (dest_x, dest_y))

            # Add frame metadata
            frames_metadata.append({
                "frame_index": frame_index,
                "x": dest_x,
                "y": dest_y,
                "width": FRAME_WIDTH,
                "height": FRAME_HEIGHT
            })

        # Add animation metadata
        metadata["animations"].append({
            "name": anim_name,
            "row": row_index,
            "frame_count": frame_count,
            "y_offset": row_index * FRAME_HEIGHT,
            "frames": frames_metadata
        })

        print(f"  ✓ Added {frame_count} frames to row {row_index}")

    # Save atlas image
    atlas_path = script_dir / "martialhero_atlas.png"
    atlas.save(atlas_path, "PNG")
    print(f"\n✓ Atlas saved: {atlas_path}")
    print(f"  Dimensions: {atlas_width}x{atlas_height}")

    # Save metadata JSON
    json_path = script_dir / "martialhero_atlas.json"
    with open(json_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"✓ Metadata saved: {json_path}")

    # Print summary
    print(f"\nSummary:")
    print(f"  Total animations: {len(ANIMATIONS)}")
    print(f"  Total frames: {sum(anim['frames'] for anim in ANIMATIONS)}")
    print(f"  Atlas size: {atlas_width}x{atlas_height}")
    print(f"  Frame size: {FRAME_WIDTH}x{FRAME_HEIGHT}")

if __name__ == "__main__":
    generate_sprite_atlas()

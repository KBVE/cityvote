#!/usr/bin/env python3
"""
Projectile Sprite Atlas Generator (Multi-Row Support)

Generates a multi-row sprite atlas from individual projectile sprites.
Each projectile gets its own row with all its animation frames.

Atlas Layout:
  Row 0: Spear (1 frame, 32x32)
  Row 1: Glaive (1 frame, 32x32)
  Row 2: Shadow Bolt (11 frames, 50x50 each, scaled to 32x32)
  Row 3: Fire Bolt (13 frames, 46x46 each, scaled to 32x32)

Usage:
    python projectile_sprite_atlas.py

Output:
    - projectile_atlas.png: Combined sprite atlas
    - projectile_atlas_metadata.json: Frame positions and projectile data
"""

import os
from PIL import Image
import json

# Configuration
TILE_SIZE = 32  # Standard tile size for atlas
ASSETS_DIR = "assets"
OUTPUT_ATLAS = "projectile_atlas.png"
OUTPUT_METADATA = "projectile_atlas_metadata.json"

# Projectile definitions (row, source_file, frame_count)
# Each projectile occupies one row
PROJECTILES = [
    {
        "name": "spear",
        "source": "spear.png",
        "frames": 1,
        "row": 0
    },
    {
        "name": "glaive",
        "source": "glaive.png",
        "frames": 1,
        "row": 1
    },
    {
        "name": "shadowbolt",
        "source": "shadowbolt/shadowbolt.png",
        "frames": 11,  # 4 moving + 7 explode
        "row": 2,
        "frame_width": 50,  # Original frame size
        "frame_height": 50,
        "animations": {
            "moving": {"start": 0, "end": 3, "count": 4},
            "explode": {"start": 4, "end": 10, "count": 7}
        }
    },
    {
        "name": "firebolt",
        "source": "firebolt/firebolt.png",
        "frames": 13,  # 6 moving + 7 explosion
        "row": 3,
        "frame_width": 46,  # Original frame size
        "frame_height": 46,
        "animations": {
            "moving": {"start": 0, "end": 5, "count": 6},
            "explode": {"start": 6, "end": 12, "count": 7}
        }
    }
]


def load_and_resize_sprite(filepath, frame_width=None, frame_height=None):
    """Load sprite and resize to TILE_SIZE x TILE_SIZE (center, preserve aspect ratio)"""
    img = Image.open(filepath).convert("RGBA")

    # For multi-frame sprites, extract individual frames
    if frame_width and frame_height:
        # This is a sprite sheet - return the full image for frame extraction
        return img
    else:
        # Single sprite - resize to tile size
        img.thumbnail((TILE_SIZE, TILE_SIZE), Image.Resampling.NEAREST)

        # Create new TILE_SIZE x TILE_SIZE canvas with transparency
        canvas = Image.new("RGBA", (TILE_SIZE, TILE_SIZE), (0, 0, 0, 0))

        # Center the sprite on canvas
        offset_x = (TILE_SIZE - img.width) // 2
        offset_y = (TILE_SIZE - img.height) // 2
        canvas.paste(img, (offset_x, offset_y), img)

        return canvas


def extract_and_resize_frame(sprite_sheet, frame_index, frame_width, frame_height):
    """Extract a single frame from sprite sheet and resize to TILE_SIZE"""
    # Calculate frame position in source sheet
    x = frame_index * frame_width
    y = 0

    # Extract frame
    frame = sprite_sheet.crop((x, y, x + frame_width, y + frame_height))

    # Resize to tile size
    frame.thumbnail((TILE_SIZE, TILE_SIZE), Image.Resampling.NEAREST)

    # Create canvas and center
    canvas = Image.new("RGBA", (TILE_SIZE, TILE_SIZE), (0, 0, 0, 0))
    offset_x = (TILE_SIZE - frame.width) // 2
    offset_y = (TILE_SIZE - frame.height) // 2
    canvas.paste(frame, (offset_x, offset_y), frame)

    return canvas


def generate_atlas():
    """Generate multi-row sprite atlas from projectile images"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    assets_path = os.path.join(script_dir, ASSETS_DIR)

    if not os.path.exists(assets_path):
        print(f"Error: Assets directory not found: {assets_path}")
        return False

    # Calculate atlas dimensions
    max_frames = max(proj["frames"] for proj in PROJECTILES)
    atlas_width = max_frames * TILE_SIZE
    atlas_height = len(PROJECTILES) * TILE_SIZE

    print(f"Atlas dimensions: {atlas_width}x{atlas_height} ({len(PROJECTILES)} rows, max {max_frames} frames)")

    # Create atlas
    atlas = Image.new("RGBA", (atlas_width, atlas_height), (0, 0, 0, 0))

    # Metadata
    metadata = {
        "tile_size": TILE_SIZE,
        "atlas_width": atlas_width,
        "atlas_height": atlas_height,
        "rows": len(PROJECTILES),
        "max_frames": max_frames,
        "projectiles": []
    }

    # Process each projectile
    for proj_data in PROJECTILES:
        name = proj_data["name"]
        source = proj_data["source"]
        frames = proj_data["frames"]
        row = proj_data["row"]

        filepath = os.path.join(assets_path, source)

        if not os.path.exists(filepath):
            print(f"Warning: Projectile not found: {filepath}")
            continue

        print(f"\nProcessing: {name} (row {row}, {frames} frame(s))")

        # Load sprite
        if "frame_width" in proj_data and "frame_height" in proj_data:
            # Multi-frame sprite sheet
            sprite_sheet = load_and_resize_sprite(
                filepath,
                proj_data["frame_width"],
                proj_data["frame_height"]
            )

            # Extract and paste each frame
            for frame_idx in range(frames):
                frame = extract_and_resize_frame(
                    sprite_sheet,
                    frame_idx,
                    proj_data["frame_width"],
                    proj_data["frame_height"]
                )

                x_pos = frame_idx * TILE_SIZE
                y_pos = row * TILE_SIZE
                atlas.paste(frame, (x_pos, y_pos), frame)
                print(f"  Frame {frame_idx}: pasted at ({x_pos}, {y_pos})")

        else:
            # Single frame sprite
            sprite = load_and_resize_sprite(filepath)
            x_pos = 0
            y_pos = row * TILE_SIZE
            atlas.paste(sprite, (x_pos, y_pos), sprite)
            print(f"  Pasted at ({x_pos}, {y_pos})")

        # Store metadata
        proj_metadata = {
            "name": name,
            "row": row,
            "frames": frames,
            "tile_size": TILE_SIZE,
            "y": row * TILE_SIZE
        }

        # Add animation data if present
        if "animations" in proj_data:
            proj_metadata["animations"] = proj_data["animations"]

        metadata["projectiles"].append(proj_metadata)

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

    # Print projectile info
    print("\n📊 Projectile Layout:")
    for proj in metadata["projectiles"]:
        print(f"  Row {proj['row']}: {proj['name']} ({proj['frames']} frame(s))")
        if "animations" in proj:
            for anim_name, anim_data in proj["animations"].items():
                print(f"    - {anim_name}: frames {anim_data['start']}-{anim_data['end']} ({anim_data['count']} frames)")

    print("\n🎨 UV Coordinates (V is constant per row):")
    for proj in metadata["projectiles"]:
        v_min = proj['y'] / atlas_height
        v_max = (proj['y'] + TILE_SIZE) / atlas_height
        print(f"  {proj['name']} (row {proj['row']}): V=[{v_min:.3f}, {v_max:.3f}]")

        if proj['frames'] > 1:
            print(f"    Frame UVs:")
            for frame_idx in range(proj['frames']):
                u_min = (frame_idx * TILE_SIZE) / atlas_width
                u_max = ((frame_idx + 1) * TILE_SIZE) / atlas_width
                print(f"      Frame {frame_idx}: U=[{u_min:.3f}, {u_max:.3f}]")

    return True


if __name__ == "__main__":
    print("🎯 Projectile Sprite Atlas Generator (Multi-Row)")
    print("=" * 50)

    success = generate_atlas()

    if success:
        print("\n✅ Atlas generation complete!")
    else:
        print("\n❌ Atlas generation failed!")
        exit(1)

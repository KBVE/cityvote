#!/usr/bin/env python3
"""
Fire Bolt Sprite Consolidator

Consolidates Move.png (6 frames) and Explosion.png (7 frames) into a single
horizontal sprite sheet: firebolt.png (13 frames total).

Frame Layout:
  Frames 0-5: Move animation (6 frames)
  Frames 6-12: Explosion animation (7 frames)

Usage:
    python fire_bolt_consolidate.py

Output:
    - firebolt.png: Consolidated sprite sheet (598x46 px, 13 frames @ 46x46 each)
"""

import os
from PIL import Image

# Configuration
FRAME_SIZE = 46  # Each frame is 46x46 pixels
MOVING_FRAMES = 6  # Move.png has 6 frames
EXPLODE_FRAMES = 7  # Explosion.png has 7 frames
TOTAL_FRAMES = MOVING_FRAMES + EXPLODE_FRAMES  # 13 total frames

INPUT_MOVING = "Move.png"
INPUT_EXPLODE = "Explosion.png"
OUTPUT_CONSOLIDATED = "firebolt.png"


def consolidate_firebolt():
    """Consolidate Move and Explosion sprites into single horizontal sheet"""
    script_dir = os.path.dirname(os.path.abspath(__file__))

    moving_path = os.path.join(script_dir, INPUT_MOVING)
    explode_path = os.path.join(script_dir, INPUT_EXPLODE)
    output_path = os.path.join(script_dir, OUTPUT_CONSOLIDATED)

    # Validate input files exist
    if not os.path.exists(moving_path):
        print(f"❌ Error: {INPUT_MOVING} not found!")
        return False

    if not os.path.exists(explode_path):
        print(f"❌ Error: {INPUT_EXPLODE} not found!")
        return False

    # Load input sprites
    print(f"Loading {INPUT_MOVING}...")
    moving_img = Image.open(moving_path).convert("RGBA")
    print(f"  Size: {moving_img.size}")

    print(f"Loading {INPUT_EXPLODE}...")
    explode_img = Image.open(explode_path).convert("RGBA")
    print(f"  Size: {explode_img.size}")

    # Validate dimensions
    expected_moving_width = MOVING_FRAMES * FRAME_SIZE
    expected_explode_width = EXPLODE_FRAMES * FRAME_SIZE

    if moving_img.size != (expected_moving_width, FRAME_SIZE):
        print(f"⚠️  Warning: Move.png size is {moving_img.size}, expected ({expected_moving_width}, {FRAME_SIZE})")

    if explode_img.size != (expected_explode_width, FRAME_SIZE):
        print(f"⚠️  Warning: Explosion.png size is {explode_img.size}, expected ({expected_explode_width}, {FRAME_SIZE})")

    # Create consolidated atlas
    atlas_width = TOTAL_FRAMES * FRAME_SIZE  # 13 * 46 = 598
    atlas_height = FRAME_SIZE  # 46
    atlas = Image.new("RGBA", (atlas_width, atlas_height), (0, 0, 0, 0))

    print(f"\nCreating consolidated atlas ({atlas_width}x{atlas_height})...")

    # Paste Move frames (frames 0-5)
    atlas.paste(moving_img, (0, 0), moving_img)
    print(f"  ✓ Pasted Move frames (0-5) at x=0")

    # Paste Explosion frames (frames 6-12)
    explode_x_offset = MOVING_FRAMES * FRAME_SIZE  # Start at x=276
    atlas.paste(explode_img, (explode_x_offset, 0), explode_img)
    print(f"  ✓ Pasted Explosion frames (6-12) at x={explode_x_offset}")

    # Save consolidated sprite sheet
    atlas.save(output_path, "PNG")
    print(f"\n✅ Consolidated sprite sheet saved: {output_path}")
    print(f"   Dimensions: {atlas_width}x{atlas_height}")
    print(f"   Total frames: {TOTAL_FRAMES}")

    # Print frame layout
    print("\n📊 Frame Layout:")
    print("  Frames 0-5:  Move animation (6 frames)")
    print("  Frames 6-12: Explosion animation (7 frames)")

    print("\n🎨 UV Coordinates:")
    for i in range(TOTAL_FRAMES):
        u_min = (i * FRAME_SIZE) / atlas_width
        u_max = ((i + 1) * FRAME_SIZE) / atlas_width
        frame_type = "Move" if i < MOVING_FRAMES else "Explosion"
        local_frame = i if i < MOVING_FRAMES else i - MOVING_FRAMES
        print(f"  Frame {i:2d} ({frame_type} {local_frame}): U=[{u_min:.4f}, {u_max:.4f}]")

    return True


if __name__ == "__main__":
    print("🔥 Fire Bolt Sprite Consolidator")
    print("=" * 50)

    success = consolidate_firebolt()

    if success:
        print("\n✅ Consolidation complete!")
    else:
        print("\n❌ Consolidation failed!")
        exit(1)

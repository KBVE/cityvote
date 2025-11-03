#!/usr/bin/env python3
"""
Shadow Bolt Sprite Consolidator

Consolidates Moving.png (4 frames) and Explode.png (7 frames) into a single
horizontal sprite sheet: shadowbolt.png (11 frames total).

Frame Layout:
  Frames 0-3: Moving animation (4 frames)
  Frames 4-10: Explode animation (7 frames)

Usage:
    python shadow_bolt_consolidate.py

Output:
    - shadowbolt.png: Consolidated sprite sheet (550x50 px, 11 frames @ 50x50 each)
"""

import os
from PIL import Image

# Configuration
FRAME_SIZE = 50  # Each frame is 50x50 pixels
MOVING_FRAMES = 4  # Moving.png has 4 frames
EXPLODE_FRAMES = 7  # Explode.png has 7 frames
TOTAL_FRAMES = MOVING_FRAMES + EXPLODE_FRAMES  # 11 total frames

INPUT_MOVING = "Moving.png"
INPUT_EXPLODE = "Explode.png"
OUTPUT_CONSOLIDATED = "shadowbolt.png"


def consolidate_shadowbolt():
    """Consolidate Moving and Explode sprites into single horizontal sheet"""
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
        print(f"⚠️  Warning: Moving.png size is {moving_img.size}, expected ({expected_moving_width}, {FRAME_SIZE})")

    if explode_img.size != (expected_explode_width, FRAME_SIZE):
        print(f"⚠️  Warning: Explode.png size is {explode_img.size}, expected ({expected_explode_width}, {FRAME_SIZE})")

    # Create consolidated atlas
    atlas_width = TOTAL_FRAMES * FRAME_SIZE  # 11 * 50 = 550
    atlas_height = FRAME_SIZE  # 50
    atlas = Image.new("RGBA", (atlas_width, atlas_height), (0, 0, 0, 0))

    print(f"\nCreating consolidated atlas ({atlas_width}x{atlas_height})...")

    # Paste Moving frames (frames 0-3)
    atlas.paste(moving_img, (0, 0), moving_img)
    print(f"  ✓ Pasted Moving frames (0-3) at x=0")

    # Paste Explode frames (frames 4-10)
    explode_x_offset = MOVING_FRAMES * FRAME_SIZE  # Start at x=200
    atlas.paste(explode_img, (explode_x_offset, 0), explode_img)
    print(f"  ✓ Pasted Explode frames (4-10) at x={explode_x_offset}")

    # Save consolidated sprite sheet
    atlas.save(output_path, "PNG")
    print(f"\n✅ Consolidated sprite sheet saved: {output_path}")
    print(f"   Dimensions: {atlas_width}x{atlas_height}")
    print(f"   Total frames: {TOTAL_FRAMES}")

    # Print frame layout
    print("\n📊 Frame Layout:")
    print("  Frames 0-3:  Moving animation (4 frames)")
    print("  Frames 4-10: Explode animation (7 frames)")

    print("\n🎨 UV Coordinates:")
    for i in range(TOTAL_FRAMES):
        u_min = (i * FRAME_SIZE) / atlas_width
        u_max = ((i + 1) * FRAME_SIZE) / atlas_width
        frame_type = "Moving" if i < MOVING_FRAMES else "Explode"
        local_frame = i if i < MOVING_FRAMES else i - MOVING_FRAMES
        print(f"  Frame {i:2d} ({frame_type} {local_frame}): U=[{u_min:.4f}, {u_max:.4f}]")

    return True


if __name__ == "__main__":
    print("⚡ Shadow Bolt Sprite Consolidator")
    print("=" * 50)

    success = consolidate_shadowbolt()

    if success:
        print("\n✅ Consolidation complete!")
    else:
        print("\n❌ Consolidation failed!")
        exit(1)

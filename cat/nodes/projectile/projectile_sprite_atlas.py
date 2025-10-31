#!/usr/bin/env python3
"""
Projectile Sprite Atlas Generator

Generates a horizontal sprite atlas from individual projectile sprites.
Each sprite is normalized to 32x32 pixels and placed in a row.

Usage:
    python projectile_sprite_atlas.py

Output:
    - projectile_atlas.png: Combined sprite atlas
    - projectile_atlas_metadata.json: Frame positions and projectile names
"""

import os
from PIL import Image
import json

# Configuration
TILE_SIZE = 32
ASSETS_DIR = "assets"
OUTPUT_ATLAS = "projectile_atlas.png"
OUTPUT_METADATA = "projectile_atlas_metadata.json"

# Projectile order (determines index in atlas)
PROJECTILE_ORDER = [
    "spear.png",
    "glaive.png",
]

def load_and_resize_sprite(filepath):
    """Load sprite and resize to TILE_SIZE x TILE_SIZE (center, preserve aspect ratio)"""
    img = Image.open(filepath).convert("RGBA")

    # Calculate scaling to fit within TILE_SIZE while preserving aspect ratio
    img.thumbnail((TILE_SIZE, TILE_SIZE), Image.Resampling.NEAREST)

    # Create new TILE_SIZE x TILE_SIZE canvas with transparency
    canvas = Image.new("RGBA", (TILE_SIZE, TILE_SIZE), (0, 0, 0, 0))

    # Center the sprite on canvas
    offset_x = (TILE_SIZE - img.width) // 2
    offset_y = (TILE_SIZE - img.height) // 2
    canvas.paste(img, (offset_x, offset_y), img)

    return canvas

def generate_atlas():
    """Generate horizontal sprite atlas from projectile images"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    assets_path = os.path.join(script_dir, ASSETS_DIR)

    if not os.path.exists(assets_path):
        print(f"Error: Assets directory not found: {assets_path}")
        return False

    # Load and process sprites
    sprites = []
    metadata = {
        "tile_size": TILE_SIZE,
        "atlas_width": 0,
        "atlas_height": TILE_SIZE,
        "projectiles": []
    }

    for idx, filename in enumerate(PROJECTILE_ORDER):
        filepath = os.path.join(assets_path, filename)

        if not os.path.exists(filepath):
            print(f"Warning: Projectile not found: {filepath}")
            continue

        print(f"Processing: {filename} (index {idx})")
        sprite = load_and_resize_sprite(filepath)
        sprites.append(sprite)

        # Store metadata
        projectile_name = os.path.splitext(filename)[0]
        metadata["projectiles"].append({
            "index": idx,
            "name": projectile_name,
            "x": idx * TILE_SIZE,
            "y": 0,
            "width": TILE_SIZE,
            "height": TILE_SIZE
        })

    if not sprites:
        print("Error: No sprites loaded!")
        return False

    # Create atlas
    atlas_width = len(sprites) * TILE_SIZE
    atlas_height = TILE_SIZE
    atlas = Image.new("RGBA", (atlas_width, atlas_height), (0, 0, 0, 0))

    # Paste sprites horizontally
    for idx, sprite in enumerate(sprites):
        x_offset = idx * TILE_SIZE
        atlas.paste(sprite, (x_offset, 0), sprite)

    # Update metadata
    metadata["atlas_width"] = atlas_width

    # Save atlas
    output_atlas_path = os.path.join(script_dir, OUTPUT_ATLAS)
    atlas.save(output_atlas_path, "PNG")
    print(f"\n✓ Atlas saved: {output_atlas_path}")
    print(f"  Size: {atlas_width}x{atlas_height} ({len(sprites)} projectiles)")

    # Save metadata
    output_metadata_path = os.path.join(script_dir, OUTPUT_METADATA)
    with open(output_metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"✓ Metadata saved: {output_metadata_path}")

    # Print UV coordinates for shader
    print("\n📊 Projectile Indices (for shader):")
    for proj in metadata["projectiles"]:
        print(f"  {proj['index']}: {proj['name']}")

    print("\n🎨 UV Coordinates per projectile:")
    for proj in metadata["projectiles"]:
        u_min = proj['x'] / atlas_width
        u_max = (proj['x'] + proj['width']) / atlas_width
        print(f"  {proj['name']}: U=[{u_min:.3f}, {u_max:.3f}]")

    return True

if __name__ == "__main__":
    print("🎯 Projectile Sprite Atlas Generator")
    print("=" * 50)

    success = generate_atlas()

    if success:
        print("\n✅ Atlas generation complete!")
    else:
        print("\n❌ Atlas generation failed!")
        exit(1)

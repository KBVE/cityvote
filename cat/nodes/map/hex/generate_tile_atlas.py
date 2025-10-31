#!/usr/bin/env python3
"""
Tile Atlas Generator for Hex Terrain
Creates a unified sprite atlas from individual tile PNGs
Output: terrain_atlas.png (320x48) + terrain_atlas_metadata.json
"""

from PIL import Image
import json
import os

# Tile order (matches TileSet source indices)
TILE_ORDER = [
    "grassland0/grassland0.png",
    "grassland1/grassland1.png",
    "grassland2/grassland2.png",
    "grassland3/grassland3.png",
    "water/water.png",
    "grassland4/grassland4.png",
    "grassland5/grassland5.png",
    "grassland_city1/grassland_city1.png",
    "grassland_city2/grassland_city2.png",
    "grassland_village1/grassland_village1.png",
]

TILE_WIDTH = 32
TILE_HEIGHT = 48

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Calculate atlas dimensions
    atlas_width = TILE_WIDTH * len(TILE_ORDER)
    atlas_height = TILE_HEIGHT

    # Create blank atlas with transparency
    atlas = Image.new('RGBA', (atlas_width, atlas_height), (0, 0, 0, 0))

    # Metadata for each tile
    metadata = {
        "atlas_width": atlas_width,
        "atlas_height": atlas_height,
        "tile_width": TILE_WIDTH,
        "tile_height": TILE_HEIGHT,
        "total_tiles": len(TILE_ORDER),
        "tiles": []
    }

    print(f"Generating {atlas_width}x{atlas_height} tile atlas...")

    # Load and paste each tile
    for idx, tile_path in enumerate(TILE_ORDER):
        full_path = os.path.join(script_dir, tile_path)

        if not os.path.exists(full_path):
            print(f"WARNING: {tile_path} not found, skipping")
            continue

        # Check if this is water tile - skip rendering it (leave transparent)
        tile_name = os.path.basename(os.path.dirname(tile_path))
        if tile_name == "water":
            print(f"  [{idx}] {tile_name:20s} - TRANSPARENT (water shader underneath)")
            # Don't paste anything - leave this section of atlas transparent
            # But still add metadata
            x_offset = idx * TILE_WIDTH
            u_start = x_offset / atlas_width
            u_end = (x_offset + TILE_WIDTH) / atlas_width
            metadata["tiles"].append({
                "index": idx,
                "name": tile_name,
                "source_path": tile_path,
                "atlas_x": x_offset,
                "atlas_y": 0,
                "uv_rect": {
                    "x": u_start,
                    "y": 0.0,
                    "width": u_end - u_start,
                    "height": 1.0
                }
            })
            continue

        # Load tile image
        tile_img = Image.open(full_path).convert('RGBA')

        # Verify dimensions
        if tile_img.size != (TILE_WIDTH, TILE_HEIGHT):
            print(f"WARNING: {tile_path} has incorrect size {tile_img.size}, expected {(TILE_WIDTH, TILE_HEIGHT)}")
            # Resize to fit
            tile_img = tile_img.resize((TILE_WIDTH, TILE_HEIGHT), Image.Resampling.NEAREST)

        # Calculate position in atlas
        x_offset = idx * TILE_WIDTH

        # Paste into atlas
        atlas.paste(tile_img, (x_offset, 0))

        # Calculate UV coordinates (0.0 to 1.0)
        u_start = x_offset / atlas_width
        u_end = (x_offset + TILE_WIDTH) / atlas_width
        v_start = 0.0
        v_end = 1.0

        # Add metadata
        tile_name = os.path.basename(os.path.dirname(tile_path))
        metadata["tiles"].append({
            "index": idx,
            "name": tile_name,
            "source_path": tile_path,
            "atlas_x": x_offset,
            "atlas_y": 0,
            "uv_rect": {
                "x": u_start,
                "y": v_start,
                "width": u_end - u_start,
                "height": v_end - v_start
            }
        })

        print(f"  [{idx}] {tile_name:20s} at x={x_offset:3d} (UV: {u_start:.4f} - {u_end:.4f})")

    # Save atlas image
    atlas_path = os.path.join(script_dir, "terrain_atlas.png")
    atlas.save(atlas_path, 'PNG')
    print(f"\n✓ Saved atlas: {atlas_path}")

    # Save metadata JSON
    metadata_path = os.path.join(script_dir, "terrain_atlas_metadata.json")
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"✓ Saved metadata: {metadata_path}")

    print(f"\nAtlas generated: {len(TILE_ORDER)} tiles, {atlas_width}x{atlas_height}px")

if __name__ == "__main__":
    main()

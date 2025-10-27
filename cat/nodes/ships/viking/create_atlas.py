#!/usr/bin/env python3
"""
Creates a 4x4 sprite atlas from 16 individual ship sprites
"""
from PIL import Image
import os

# Get the directory where this script is located
script_dir = os.path.dirname(os.path.abspath(__file__))

# Load all 16 ship sprites
sprites = []
for i in range(1, 17):
    img_path = os.path.join(script_dir, f"ship{i}.png")
    if os.path.exists(img_path):
        sprites.append(Image.open(img_path))
    else:
        print(f"Warning: {img_path} not found")

if len(sprites) != 16:
    print(f"Error: Expected 16 sprites, found {len(sprites)}")
    exit(1)

# Get dimensions of first sprite (assuming all are same size)
sprite_width, sprite_height = sprites[0].size
print(f"Sprite size: {sprite_width}x{sprite_height}")

# Create 4x4 atlas
atlas_width = sprite_width * 4
atlas_height = sprite_height * 4
atlas = Image.new('RGBA', (atlas_width, atlas_height), (0, 0, 0, 0))

# Arrange sprites in 4x4 grid
# Row 0: sprites 0-3 (directions 0, 1, 2, 3)
# Row 1: sprites 4-7 (directions 4, 5, 6, 7)
# Row 2: sprites 8-11 (directions 8, 9, 10, 11)
# Row 3: sprites 12-15 (directions 12, 13, 14, 15)
for idx, sprite in enumerate(sprites):
    col = idx % 4
    row = idx // 4
    x = col * sprite_width
    y = row * sprite_height
    atlas.paste(sprite, (x, y))
    print(f"Placed sprite {idx+1} (direction {idx}) at ({x}, {y})")

# Save atlas
output_path = os.path.join(script_dir, "viking_atlas.png")
atlas.save(output_path)
print(f"\nAtlas created: {output_path}")
print(f"Atlas size: {atlas_width}x{atlas_height}")

#!/usr/bin/env python3
"""
Generate sprite atlas for social media logos
Resizes discord.png and twitch.png to 32x32 and combines them into a sprite atlas
"""

from PIL import Image
import json
import os

# Configuration
LOGO_DIR = "logo"
OUTPUT_DIR = "."
ATLAS_NAME = "sprite_social_logos_atlas.png"
JSON_NAME = "sprite_social_logos_atlas.json"
LOGO_SIZE = 32  # 32x32 pixels per logo

# Logo files in order
LOGOS = [
    "discord.png",
    "twitch.png"
]

def resize_with_transparency(img, size):
    """Resize image to size x size, maintaining transparency"""
    # Convert to RGBA if not already
    if img.mode != 'RGBA':
        img = img.convert('RGBA')

    # Resize with high-quality resampling
    return img.resize((size, size), Image.Resampling.LANCZOS)

def create_atlas():
    """Create sprite atlas from logo images"""
    logo_count = len(LOGOS)
    atlas_width = LOGO_SIZE * logo_count
    atlas_height = LOGO_SIZE

    # Create blank RGBA image for atlas
    atlas = Image.new('RGBA', (atlas_width, atlas_height), (0, 0, 0, 0))

    # Atlas metadata
    atlas_data = {
        "size": {"width": atlas_width, "height": atlas_height},
        "logo_size": LOGO_SIZE,
        "logos": []
    }

    # Process each logo
    for i, logo_file in enumerate(LOGOS):
        logo_path = os.path.join(LOGO_DIR, logo_file)

        if not os.path.exists(logo_path):
            print(f"Warning: {logo_path} not found, skipping...")
            continue

        print(f"Processing {logo_file}...")

        # Load and resize logo
        logo_img = Image.open(logo_path)
        resized_logo = resize_with_transparency(logo_img, LOGO_SIZE)

        # Calculate position in atlas
        x = i * LOGO_SIZE
        y = 0

        # Paste logo into atlas
        atlas.paste(resized_logo, (x, y), resized_logo)

        # Add metadata
        logo_name = os.path.splitext(logo_file)[0]
        atlas_data["logos"].append({
            "name": logo_name,
            "index": i,
            "x": x,
            "y": y,
            "width": LOGO_SIZE,
            "height": LOGO_SIZE
        })

        print(f"  Added '{logo_name}' at position ({x}, {y})")

    # Save atlas
    atlas_output = os.path.join(OUTPUT_DIR, ATLAS_NAME)
    atlas.save(atlas_output, 'PNG')
    print(f"\nAtlas saved to: {atlas_output}")
    print(f"Atlas size: {atlas_width}x{atlas_height} ({logo_count} logos)")

    # Save JSON metadata
    json_output = os.path.join(OUTPUT_DIR, JSON_NAME)
    with open(json_output, 'w') as f:
        json.dump(atlas_data, f, indent=2)
    print(f"Metadata saved to: {json_output}")

    return atlas_data

if __name__ == "__main__":
    print("Social Media Logo Atlas Generator")
    print("=" * 50)

    atlas_data = create_atlas()

    print("\n" + "=" * 50)
    print("Atlas generation complete!")
    print("\nAtlas data:")
    print(json.dumps(atlas_data, indent=2))

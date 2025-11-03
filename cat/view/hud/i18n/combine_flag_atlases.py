#!/usr/bin/env python3
"""
Combines realcountries.png and realcountries2.png into a single atlas.
Updates the JSON metadata with new coordinates.
"""

import json
from PIL import Image
import os

# Get the directory where this script is located
script_dir = os.path.dirname(os.path.abspath(__file__))

# Input files
atlas1_path = os.path.join(script_dir, "realcountries.png")
atlas2_path = os.path.join(script_dir, "realcountries2.png")
json1_path = os.path.join(script_dir, "realcountriesJson.json")
json2_path = os.path.join(script_dir, "realcountries2json.json")

# Output files
output_atlas_path = os.path.join(script_dir, "flags_combined.png")
output_json_path = os.path.join(script_dir, "flags_combined.json")

def main():
    print("Loading atlas images...")

    # Load the two atlas images
    atlas1 = Image.open(atlas1_path)
    atlas2 = Image.open(atlas2_path)

    print(f"Atlas 1 size: {atlas1.size}")
    print(f"Atlas 2 size: {atlas2.size}")

    # Calculate combined dimensions (stack horizontally)
    combined_width = atlas1.width + atlas2.width
    combined_height = max(atlas1.height, atlas2.height)

    print(f"Combined size: {combined_width}x{combined_height}")

    # Create combined image
    combined = Image.new('RGBA', (combined_width, combined_height), (0, 0, 0, 0))

    # Paste atlas1 at (0, 0)
    combined.paste(atlas1, (0, 0))

    # Paste atlas2 at (atlas1.width, 0)
    combined.paste(atlas2, (atlas1.width, 0))

    # Save combined atlas
    combined.save(output_atlas_path)
    print(f"Saved combined atlas to: {output_atlas_path}")

    # Load JSON metadata
    print("\nCombining JSON metadata...")

    with open(json1_path, 'r') as f:
        json1_data = json.load(f)

    with open(json2_path, 'r') as f:
        json2_data = json.load(f)

    # Combine frames
    combined_frames = {}

    # Add frames from atlas1 (no coordinate change needed)
    if "frames" in json1_data:
        for flag_name, frame_data in json1_data["frames"].items():
            combined_frames[flag_name] = frame_data
            print(f"  Added {flag_name} from atlas1 at ({frame_data['frame']['x']}, {frame_data['frame']['y']})")

    # Add frames from atlas2 (shift x coordinate by atlas1.width)
    if "frames" in json2_data:
        for flag_name, frame_data in json2_data["frames"].items():
            # Deep copy the frame data
            new_frame_data = {
                "frame": {
                    "x": frame_data["frame"]["x"] + atlas1.width,  # Shift x coordinate
                    "y": frame_data["frame"]["y"],
                    "w": frame_data["frame"]["w"],
                    "h": frame_data["frame"]["h"]
                },
                "rotated": frame_data.get("rotated", False),
                "trimmed": frame_data.get("trimmed", False),
                "spriteSourceSize": frame_data.get("spriteSourceSize", {}),
                "sourceSize": frame_data.get("sourceSize", {})
            }
            combined_frames[flag_name] = new_frame_data
            print(f"  Added {flag_name} from atlas2 at ({new_frame_data['frame']['x']}, {new_frame_data['frame']['y']})")

    # Create combined JSON
    combined_json = {
        "frames": combined_frames,
        "meta": {
            "app": "Combined by Python script",
            "version": "1.0",
            "image": "flags_combined.png",
            "size": {"w": combined_width, "h": combined_height},
            "scale": "1"
        }
    }

    # Save combined JSON
    with open(output_json_path, 'w') as f:
        json.dump(combined_json, f, indent=2)

    print(f"\nSaved combined JSON to: {output_json_path}")
    print(f"\nTotal flags: {len(combined_frames)}")

    # Print some statistics
    print("\n=== Flag List ===")
    for flag_name in sorted(combined_frames.keys()):
        frame = combined_frames[flag_name]["frame"]
        print(f"  {flag_name:20s} -> ({frame['x']:3d}, {frame['y']:3d}) [{frame['w']}x{frame['h']}]")

if __name__ == "__main__":
    main()

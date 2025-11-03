#!/usr/bin/env python3
"""
Evil Wizard 3 (Skull Wizard) Atlas Generator

Combines all animation sheets into a single vertical atlas.
Each animation sheet becomes one row.

Asset Pack Info:
- Evil Wizard 3 is a free 33 x 53 pixels asset pack with 8 animation sprites
- Sprite dimensions: 33x53 pixels per frame
- 8 different animations

Animation Details:
- Idle    - 10 frames
- Walk    - 8 frames
- Run     - 8 frames
- Jump    - 3 frames
- Fall    - 3 frames
- Attack  - 13 frames
- Get Hit - 3 frames
- Death   - 18 frames
"""

import subprocess
from pathlib import Path

# Animation sheets in order (matching expected AnimType enum)
# Frame counts listed next to each animation
SHEETS = [
    "Idle.png",        # Row 0: 10 frames
    "Walk.png",        # Row 1: 8 frames
    "Run.png",         # Row 2: 8 frames
    "Jump.png",        # Row 3: 3 frames
    "Fall.png",        # Row 4: 3 frames
    "Attack.png",      # Row 5: 13 frames
    "Get hit.png",     # Row 6: 3 frames
    "Death.png",       # Row 7: 18 frames
]

# Frame counts for documentation and validation
FRAME_COUNTS = {
    "Idle.png": 10,
    "Walk.png": 8,
    "Run.png": 8,
    "Jump.png": 3,
    "Fall.png": 3,
    "Attack.png": 13,
    "Get hit.png": 3,
    "Death.png": 18,
}

script_dir = Path(__file__).parent
output_path = script_dir / "skullwizard_atlas.png"

print("Creating Skull Wizard atlas...")
print(f"Sprite dimensions: 33x53 pixels per frame")
print(f"Total animations: {len(SHEETS)}")
print(f"Total frames: {sum(FRAME_COUNTS.values())}")

# Build list of sheet paths (files are in same directory as script)
sheet_paths = [str(script_dir / sheet) for sheet in SHEETS]

# Check if all sheets exist
missing_files = []
for sheet in sheet_paths:
    if not Path(sheet).exists():
        missing_files.append(sheet)
        print(f"❌ Missing file: {sheet}")

if missing_files:
    print(f"\n❌ Error: {len(missing_files)} file(s) missing")
    exit(1)

# Use ImageMagick to stack vertically
# -append stacks images vertically
# -background none preserves transparency
cmd = ["magick"] + sheet_paths + ["-background", "none", "-append", str(output_path)]

print(f"\nRunning ImageMagick with {len(sheet_paths)} animation sheets...")
result = subprocess.run(cmd, capture_output=True, text=True)

if result.returncode != 0:
    print(f"❌ ImageMagick Error: {result.stderr}")
    exit(1)

print(f"\n✅ Atlas created: {output_path}")

# Show atlas dimensions
result = subprocess.run(["identify", str(output_path)], capture_output=True, text=True)
if result.returncode == 0:
    print(f"\nAtlas Info:\n{result.stdout}")

print("\nAtlas Layout:")
for i, sheet in enumerate(SHEETS):
    frame_count = FRAME_COUNTS[sheet]
    print(f"  Row {i}: {sheet:15} - {frame_count:2} frames")

print("\n✅ Skull Wizard sprite atlas generation complete!")

#!/usr/bin/env python3
"""
King Atlas Generator
Combines all animation sheets into a single vertical atlas
Each animation sheet becomes one row
"""

import subprocess
from pathlib import Path

# Animation sheets in order (matching enum AnimType)
# Frame counts: Idle=8, Run=8, Jump=2, Fall=2, Attack1=4, Attack2=4, Attack3=4, Take Hit=4, Death=6
SHEETS = [
    "Idle.png",        # Row 0: 8 frames
    "Run.png",         # Row 1: 8 frames
    "Jump.png",        # Row 2: 2 frames
    "Fall.png",        # Row 3: 2 frames
    "Attack1.png",     # Row 4: 4 frames
    "Attack2.png",     # Row 5: 4 frames
    "Attack3.png",     # Row 6: 4 frames
    "Take Hit.png",    # Row 7: 4 frames
    "Death.png",       # Row 8: 6 frames
]

script_dir = Path(__file__).parent
sprite_dir = script_dir / "sprite"
output_path = script_dir / "king_atlas.png"

print("Creating King atlas...")
print(f"Sheets: {len(SHEETS)}")

# Build list of sheet paths from sprite directory
sheet_paths = [str(sprite_dir / sheet) for sheet in SHEETS]

# Check if all sheets exist
for sheet in sheet_paths:
    if not Path(sheet).exists():
        print(f"❌ Missing file: {sheet}")
        exit(1)

# Use ImageMagick to stack vertically
# -append stacks images vertically
# -background none preserves transparency
cmd = ["magick"] + sheet_paths + ["-background", "none", "-append", str(output_path)]

print(f"\nRunning magick with {len(sheet_paths)} sheets...")
result = subprocess.run(cmd, capture_output=True, text=True)

if result.returncode != 0:
    print(f"❌ Error: {result.stderr}")
    exit(1)

print(f"\n✅ Atlas created: {output_path}")

# Show atlas dimensions
result = subprocess.run(["identify", str(output_path)], capture_output=True, text=True)
print(result.stdout)

print("\nAtlas Layout:")
for i, sheet in enumerate(SHEETS):
    print(f"  Row {i}: {sheet}")

#!/usr/bin/env python3
"""
Fantasy Warrior Atlas Generator
Combines all animation sheets into a single vertical atlas
Each animation sheet becomes one row
"""

import subprocess
from pathlib import Path

# Animation sheets in order (matching enum AnimType)
# Frame counts: Idle=10, Run=8, Jump=3, Fall=3, Attack1=7, Attack2=7, Attack3=8, Take Hit=3, Death=7
SHEETS = [
    "Idle.png",        # Row 0: 10 frames (27x45 each)
    "Run.png",         # Row 1: 8 frames
    "Jump.png",        # Row 2: 3 frames
    "Fall.png",        # Row 3: 3 frames
    "Attack1.png",     # Row 4: 7 frames
    "Attack2.png",     # Row 5: 7 frames
    "Attack3.png",     # Row 6: 8 frames
    "Take hit.png",    # Row 7: 3 frames
    "Death.png",       # Row 8: 7 frames
]

script_dir = Path(__file__).parent
output_path = script_dir / "fantasy_warrior_atlas.png"

print("Creating Fantasy Warrior atlas...")
print(f"Sprite size: 27x45 pixels")
print(f"Sheets: {len(SHEETS)}")

# Build list of sheet paths
sheet_paths = [str(script_dir / sheet) for sheet in SHEETS]

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

#!/usr/bin/env python3
"""
Simple atlas generator - just stack the sheets vertically
Each sheet becomes one row in the atlas
"""

import subprocess
from pathlib import Path

# Just list the sheet files in order
# NOTE: Skipping idle (248px) since it doesn't fit 128px frame pattern
# We'll use walk frame 0 as idle instead
SHEETS = [
    "raptor-walk.png",           # Row 0 (use as IDLE)
    "raptor-walk.png",           # Row 1 (WALK)
    "raptor-run.png",            # Row 2 (RUN)
    "raptor-bite.png",           # Row 3 (BITE)
    "raptor-pounce.png",         # Row 4 (POUNCE)
    "raptor-ready-pounce.png",   # Row 5 (POUNCE_READY)
    "raptor-pounce-end.png",     # Row 6 (POUNCE_END)
    "raptor-pounce-latched.png", # Row 7 (POUNCE_LATCHED)
    "raptor-pounced-attack.png", # Row 8 (POUNCED_ATTACK)
    "raptor-roar.png",           # Row 9 (ROAR)
    "raptor-scanning.png",       # Row 10 (SCANNING)
    "raptor-on-hit.png",         # Row 11 (ON_HIT)
    "raptor-dead.png",           # Row 12 (DEAD)
    "raptor-jump.png",           # Row 13 (JUMP)
    "raptor-falling.png",        # Row 14 (FALLING)
]

script_dir = Path(__file__).parent
sheets_dir = script_dir / "sheets"
output_path = script_dir / "jezza_atlas.png"

print("Creating atlas by vertically stacking sheets...")

# Build list of sheet paths
sheet_paths = [str(sheets_dir / sheet) for sheet in SHEETS]

# Use ImageMagick append to stack vertically
# -append stacks images vertically
cmd = ["magick"] + sheet_paths + ["-background", "none", "-append", str(output_path)]

print(f"Running magick with {len(sheet_paths)} sheets...")
subprocess.run(cmd, check=True)

print(f"\n✓ Atlas created: {output_path}")
subprocess.run(["identify", str(output_path)])

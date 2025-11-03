#!/usr/bin/env python3
"""
Create a sprite atlas from individual playing card images.

Layout: 13 columns × 5 rows
  Rows 0-3: Standard suits (clubs, diamonds, hearts, spades) values 1-13
  Row 4: Custom cards (vikings-53, dino-54 at positions 0-1)
Output: 1248×720 PNG (96×144 per card)
"""

from PIL import Image
import os

# Configuration
CARD_WIDTH = 96
CARD_HEIGHT = 144
CARDS_PER_ROW = 13
NUM_ROWS = 5  # 4 standard suits + 1 custom row

# Atlas dimensions
ATLAS_WIDTH = CARD_WIDTH * CARDS_PER_ROW  # 1248
ATLAS_HEIGHT = CARD_HEIGHT * NUM_ROWS     # 720

# Suit order (matches the row order in the atlas)
SUITS = ['clubs', 'diamonds', 'hearts', 'spades']

# Custom cards (row 4)
CUSTOM_CARDS = [
    ('vikings', 52),      # Position 0 in row 4 (card_id = 52)
    ('dino', 53),         # Position 1 in row 4 (card_id = 53)
    ('baron', 54),        # Position 2 in row 4 (card_id = 54)
    ('skull-wizard', 55), # Position 3 in row 4 (card_id = 55)
    ('warrior', 56),      # Position 4 in row 4 (card_id = 56)
    ('fireworm', 57),     # Position 5 in row 4 (card_id = 57)
]

# Paths
CARDS_DIR = '.'
OUTPUT_PATH = './card_atlas.png'

def validate_card_dimensions():
    """Validate that all cards are the correct size before building atlas."""
    print("=" * 60)
    print("STEP 1: VALIDATING CARD DIMENSIONS")
    print("=" * 60)
    print()

    all_valid = True
    invalid_cards = []

    # Check standard cards
    print("Checking standard cards (52 cards)...")
    for suit in SUITS:
        for value in range(1, 14):
            card_filename = f'card-{suit}-{value}.png'
            card_path = os.path.join(CARDS_DIR, card_filename)

            if not os.path.exists(card_path):
                print(f"  ❌ MISSING: {card_filename}")
                invalid_cards.append(card_filename)
                all_valid = False
                continue

            try:
                with Image.open(card_path) as img:
                    if img.size != (CARD_WIDTH, CARD_HEIGHT):
                        print(f"  ❌ WRONG SIZE: {card_filename} is {img.size}, expected {CARD_WIDTH}×{CARD_HEIGHT}")
                        invalid_cards.append(card_filename)
                        all_valid = False
            except Exception as e:
                print(f"  ❌ ERROR: {card_filename} - {e}")
                invalid_cards.append(card_filename)
                all_valid = False

    # Check custom cards
    print()
    print(f"Checking custom cards ({len(CUSTOM_CARDS)} cards)...")
    for card_name, card_id in CUSTOM_CARDS:
        card_filename = f'card-{card_name}-{card_id}.png'
        card_path = os.path.join(CARDS_DIR, 'custom', card_filename)

        if not os.path.exists(card_path):
            print(f"  ❌ MISSING: custom/{card_filename}")
            invalid_cards.append(f"custom/{card_filename}")
            all_valid = False
            continue

        try:
            with Image.open(card_path) as img:
                if img.size != (CARD_WIDTH, CARD_HEIGHT):
                    print(f"  ❌ WRONG SIZE: custom/{card_filename} is {img.size}, expected {CARD_WIDTH}×{CARD_HEIGHT}")
                    invalid_cards.append(f"custom/{card_filename}")
                    all_valid = False
        except Exception as e:
            print(f"  ❌ ERROR: custom/{card_filename} - {e}")
            invalid_cards.append(f"custom/{card_filename}")
            all_valid = False

    print()
    if all_valid:
        print(f"✅ All {52 + len(CUSTOM_CARDS)} cards validated successfully!")
        print()
        return True
    else:
        print(f"❌ Found {len(invalid_cards)} invalid card(s):")
        for card in invalid_cards:
            print(f"   - {card}")
        print()
        print("Please fix the above issues before creating the atlas.")
        return False

def create_card_atlas():
    """Create the card atlas from individual card images."""

    print("=" * 60)
    print("STEP 2: CREATING CARD ATLAS")
    print("=" * 60)
    print()

    # Create blank atlas
    atlas = Image.new('RGBA', (ATLAS_WIDTH, ATLAS_HEIGHT), (0, 0, 0, 0))

    print(f"Creating card atlas: {ATLAS_WIDTH}×{ATLAS_HEIGHT}")
    print(f"Card size: {CARD_WIDTH}×{CARD_HEIGHT}")
    print()

    cards_placed = 0

    # Iterate through each suit (row)
    for row_idx, suit in enumerate(SUITS):
        print(f"Processing {suit}...")

        # Iterate through each value (column)
        for value in range(1, 14):  # 1-13
            # Build the file path
            card_filename = f'card-{suit}-{value}.png'
            card_path = os.path.join(CARDS_DIR, card_filename)

            # Check if file exists
            if not os.path.exists(card_path):
                print(f"  WARNING: Missing {card_filename}")
                continue

            # Load the card image
            try:
                card_img = Image.open(card_path)

                # Verify dimensions
                if card_img.size != (CARD_WIDTH, CARD_HEIGHT):
                    print(f"  WARNING: {card_filename} has wrong size: {card_img.size}")
                    # Resize if needed
                    card_img = card_img.resize((CARD_WIDTH, CARD_HEIGHT), Image.LANCZOS)

                # Calculate position in atlas
                col_idx = value - 1  # 0-12
                x = col_idx * CARD_WIDTH
                y = row_idx * CARD_HEIGHT

                # Paste card into atlas
                atlas.paste(card_img, (x, y))
                cards_placed += 1

            except Exception as e:
                print(f"  ERROR loading {card_filename}: {e}")

    print()
    print(f"Placed {cards_placed}/52 standard cards")

    # Add custom cards (row 4)
    print()
    print("Processing custom cards...")
    custom_cards_placed = 0

    for col_idx, (card_name, card_id) in enumerate(CUSTOM_CARDS):
        card_filename = f'card-{card_name}-{card_id}.png'
        card_path = os.path.join(CARDS_DIR, 'custom', card_filename)

        if not os.path.exists(card_path):
            print(f"  WARNING: Missing {card_filename}")
            continue

        try:
            card_img = Image.open(card_path)

            # Verify dimensions
            if card_img.size != (CARD_WIDTH, CARD_HEIGHT):
                print(f"  WARNING: {card_filename} has wrong size: {card_img.size}")
                card_img = card_img.resize((CARD_WIDTH, CARD_HEIGHT), Image.LANCZOS)

            # Calculate position in atlas (row 4)
            x = col_idx * CARD_WIDTH
            y = 4 * CARD_HEIGHT

            # Paste card into atlas
            atlas.paste(card_img, (x, y))
            custom_cards_placed += 1
            print(f"  Placed {card_filename} at position ({col_idx}, 4)")

        except Exception as e:
            print(f"  ERROR loading {card_filename}: {e}")

    print()
    print(f"Placed {custom_cards_placed}/{len(CUSTOM_CARDS)} custom cards")
    print(f"Total: {cards_placed + custom_cards_placed} cards in atlas")

    # Save the atlas
    print()
    print(f"Saving atlas to: {OUTPUT_PATH}")
    atlas.save(OUTPUT_PATH, 'PNG', optimize=True)

    print("Done!")
    print()
    print("Atlas layout:")
    print("  Row 0: Clubs      (1-13)")
    print("  Row 1: Diamonds   (1-13)")
    print("  Row 2: Hearts     (1-13)")
    print("  Row 3: Spades     (1-13)")
    print("  Row 4: Custom     (vikings-52, dino-53, baron-54, skull-wizard-55, warrior-56, fireworm-57)")
    print()
    print("UV calculation:")
    print("  Standard cards (0-51):")
    print("    card_id = suit * 13 + (value - 1)")
    print("    col = card_id % 13")
    print("    row = card_id / 13")
    print("  Custom cards:")
    print("    vikings-52:      col=0, row=4")
    print("    dino-53:         col=1, row=4")
    print("    baron-54:        col=2, row=4")
    print("    skull-wizard-55: col=3, row=4")
    print("    warrior-56:      col=4, row=4")
    print("    fireworm-57:     col=5, row=4")
    print()
    print("  uv_x = col / 13.0")
    print("  uv_y = row / 5.0")
    print("  uv_width = 1.0 / 13.0")
    print("  uv_height = 1.0 / 5.0")

if __name__ == '__main__':
    # Get the script directory and make paths relative to it
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    # Step 1: Validate all card dimensions
    if not validate_card_dimensions():
        print("Aborting atlas creation due to validation errors.")
        exit(1)

    # Step 2: Create the atlas
    create_card_atlas()

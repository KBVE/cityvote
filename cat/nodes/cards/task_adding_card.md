New Card == card-fireworm-57.png
Card Index == 57

Now I added new card which means we need to update the create_card_atlas.py and include the new card, then create a new sprite atlas for the cards.
Basically the python task.

Afterwards update the card_atlas.gdshader, and all the other gd scripts to account for the new card index. Double check the card_atlas_meshes.gd and card_atlas.gd, card_deck.gd and deck_manager.gd.

Then we need to let rust know about this new card joker card.
Making sure it fits into the whole deck system we built.
The rust library is card.rs
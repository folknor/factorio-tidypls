# Tidy Pls!

Robos tidy things tip top in the trenches of their territory. Terrific!

This is a blatant fork of Utoxin's awesomesauce [Concreep Redux](https://github.com/utoxin/concreep-redux) because my values do not align with their values.

These are my values:

1. The number of times I've killed my brother in Quake 1 deathmatch. It's hundreds, but the exact value is secret.
2.  42.
3. The number of packets of sour cabbage available in your local grocery store (whichever is the closest one that stocks sour cabbage), modulated by the number of routes driven by the person with the lowest Bacon number from you who does deliveries full time.

Obviously with these values I can never see eye to eye with Utoxin.

Please check out [my other addons](https://mods.factorio.com/user/folk) as well! For example [Blueprint Janitor](https://mods.factorio.com/mods/folk/folk-janitor) or [Shuttle Train Lite](https://mods.factorio.com/mod/folk-shuttle).

I also recommend the mod [Clean Floor](https://mods.factorio.com/mod/CleanFloor) by Skrundz alongside Tidy Pls!. It will remove any decorations below paved areas (grass that would stick out from the concrete, etc).

Please be aware that if your defensive perimiter depends on cliffs, activating this mod might result in the cliffs being removed at some point (if there are construction areas from roboports that extend over them, and if the logistic network contains more than 100 cliff explosives)!

## Key differences

The entire codebase is rewritten to be top-down rather than bottom-up. That is to say, the mod works by working with each logistic network instead of each roboport. However this is irrelevant to the end user. These are the relevant parts for normal users:

-   Zero config.
-   Doesn't do landfills or patterns.
-   Unlocks by tech and has a keybinding and button to toggle the mod on/off.
-   Hopefully, potentially, it could have less impact on UPS because of the top-down approach.

## How it works

The mod builds stone/concrete/refined concrete around all roboports slowly. Like the Zerg creep from Starcraft it grows outwards.

1. Every 30 seconds, it looks at each logistic network and finds the number of available bots.
2. 10% of available bots are allocated.
3. The number of normal-quality Refined Concrete, Concrete, and Stone Brick in each network is calculated, always saving at least 100 of each.
4. Every roboport is checked whether its entire construction area is covered in any of the 3 kinds, and if not then it builds outwards from the center.
5. If there are still bots available, it checks to see if any area is covered by inferior types of tiles (Refined is better than Concrete is better than Stone), and upgrades as necessary.
6. If at any point it finds trees, rocks, or other annoyances, these will be cleared by bots first.
7. If at any point it finds cliffs, and theres more than 100 cliff explosives available in the network, the cliffs will be cleared.

Obviously once the allocated bots are used, it doesn't issue further orders until the next 30-second interval.

The mod tries to expand coverage rather than upgrade existing tiles. For example if you run out of Refined Concrete after some time expanding, it will continue to expand using Concrete and/or Stone Brick, and then start using Refined again when it's available without upgrading the Concrete/Stone it put down in the meantime. However, once it's done expanding, it will then go back and upgrade those.

If you add the mod to an existing game where some surfaces are already covered by any of the tiles, the mod might spend a few minutes calculating before it starts doing anything. Also, it might upgrade quite a bit of the existing Concrete/Stone to Refined/Concrete before expanding, contrary to the paragraph above. Fear not, however - after a few minutes it will continue expanding instead.

## Changelog

Please see changelog.txt or the changelog tab on factorios mod portal, or look at the [commit history](https://github.com/folknor/factorio-tidypls/commits/main/) on github.

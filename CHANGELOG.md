# Gamepad QoL

## 0.4.0

- Track and untrack quests with one button: in the Map & Quest Log, put the cursor on a quest and press L3. On a zone header it tracks all its quests, or untracks them if they're all tracked. It works on a quest's details page too. With the map side focused, L3 is still the map marker.
- Feed pet (hunters): hold RB and press R3 to feed your pet without opening your bags. It picks food your pet eats at most 10 levels below it (the lowest of those, so better food lasts), or else the highest-level food it will eat. Casting Feed Pet from the action bar opens the gamepad bags, and they could close again straight away.
- Both buttons can be changed in the settings, and they're in the button guide, which shows once more so you can try them.

## 0.3.0

- Junk to sell or destroy: when your bags fill up, what should go first? The cheapest junk gets the game's junk coin and a number, 1 for the first to go, by what a vendor pays for the whole stack. The bag window's bottom bar says how many and what they're worth ("5 to sell or destroy · 23c"), and the item's tooltip its place.
- Pick what counts (greys only, greys and whites, or greens too), how many to mark (1 to 5), whether to show the marks always or only when your bags are nearly full, and the look: Faded (the item dimmed and greyed; the default), Sell tag, Gold glow, Red wash or Coin only.
- Never marked: food, drink, potions and other consumables; cloth, ore, herbs and other trade goods; reagents, recipes, quest items, ammunition and keys; profession and class tools (mining picks, skinning knives, blacksmith hammers, enchanting rods, fishing poles, thieves' tools, totems) and your hearthstone; items a quest in your log still needs.
- Settings have their own window, made for the controller: D-pad up and down pick a setting, left and right (or A) change it, B closes; the mouse works too. Open it with /gqol, with Y in the button guide, or from Options > AddOns > Gamepad QoL. The mark style shows a preview. (Blizzard's own Settings window upset the gamepad UI when it closed with an addon's settings in it.)
- The Key Bindings entries are gone, for the same reason: Clean Up, quick invite and the peek map are on controller buttons.

## 0.2.0

- Clean Up Bags: press L3 while your bags are open (it's shown in the button bar under your bags). There's also a key binding, and a setting to clean up every time you close your bags (off to start with). It's no longer on the Y menu: an addon's entry there upset the game's gamepad menus and caused an error.
- Quick invite: target the mob you need for a quest and hold RT and press R3 to invite the player who's killing it. With a player targeted, it invites them. It doesn't work while you're in combat.
- Peek map: hold LT and hold R3 to see the map; let go of R3 to close it. You keep moving while it's up.
- Controller buttons: each of these can go on another button or combination in the settings. Combinations (a trigger or shoulder held with a stick click) work outside combat; R3 alone stays the game's ping. If Improved Forever is installed, they start unset so the two don't fight over buttons.
- Button guide: on first login a window lists your buttons; each one lights up when you try it. Open it again from the settings or with /gqol guide.
- Bag buttons: the row now runs backpack first, from the left; moving the cursor left and right along it works; and the keyring no longer causes an error.
- Thanks to Improved Forever (markgravity) for showing how to add controller buttons without upsetting the game's gamepad UI.

## 0.1.0

- Bag buttons: the backpack and bag buttons come out of the item grid in the gamepad bag window and sit in their own row above your items (or in a column down the left side, in the settings).
- Clean Up Bags: press Y on any item in your bags and Clean Up Bags is at the top of the menu.
- Cheapest items: the item that sells to a vendor for the least (whole stack) gets a copper coin and an orange glow, so you know what to drop when your bags are full. You can mark up to 5, numbered 1 (the cheapest, first to go) to 5. Items that can't be sold are never marked.
- Settings: Options > AddOns > Gamepad QoL, or /gqol.

# DFHack Compendium
A collection of DFHack mods, experiments, and reference notes created while exploring and extending Dwarf Fortress through scripting.

***
*Note: I prefer Adventure Mode to Fortress Mode so the mods may need to be modified to work in Fort Mode.*

## Mods
* **Dynamic Party**: Makes party members more autonomous. As of right now, NPCs will equip the best weapon in their inventory based on their highest melee skill. Its a WIP so it has its quirks.
* **Party Add**: Add any NPC to your adventurer party. Needs a little work as some NPCs will leave the party if they're too far from home or if they can't path to the player.
* **Party Remove**: Removes any NPC from your adventurer party.
* **Random Event**: A random event occurs on a set interval. A good way to add chaos to your playthrough. Needs more events though. Events work in both Adventure and Fortress Mode.
  - **Berserk Event**: A random unit will become berserk.
  - **Give Unit Random Syndrome Event**: A random unit is given a random syndrome. 
  - **Instant Baby Event**: A random adult male/adult female will instantly have a baby.
  - **Make Unit Vampire Event**: Doesn't work. Its supposed to select a random unit and turn them into a vampire. Can still happen with the **Give Unit Random Syndrome Event** though.
  - **Pickpocket Event**: A random unit will have one their items taken by another unit that's within a 1 tile radius of them.
  - **Random Pregnancy Event**: A random adult male/adult female will conceive with a default 9 months gestation.
  - **Random Teleport Event**: A random unit will be teleported to a random x,y,z position.
  - **Unit On Fire Event**: A random unit will be set on fire.
* **Random Pregnancy**: Chooses a random adult male and adult female to have a kid. The child is born 9 months later. It is very random as weird couplings can happen. Perhaps a chipmunk man and an elephant woman shouldn't have kids...
* **Set Book Title**: Allows you to change the name of written books.

***
## Dynamic Party
* **dynamic-party once**: Will fire the dynamic party script once.
* **dynamic-party start [ticks]**: Will fire the dynamic party script periodically. Example: dynamic-party start 100

### Features & Bugs
* Companions will automatically equip the best weapon available in their inventory based on their highest melee skill level.
* The companion sprites don't automatically update so they may appear to be holding a weapon that they dropped or may not appear to be holding a weapon at all, even though they are.

### Automatic Running
If you want this mod to run automatically without having to call it in the DFHack console, add **dynamic-party start [ticks]** to the **onLoad.init** file inside of **dfhack-config\init**.

*** 
## Party Add / Remove
While examining a NPC enter **party-add** or **party-remove** to add/remove them to/from your party.

***
## Random Event
* **random-event once**: Will try to fire a random event once.
* **random-event start [ticks]**: Will try to fire a random event periodically. Example: random-event start 100
* **random-event stop**: Will stop firing.
* **random-event interval [ticks]**: Updates firing interval. Example: random-event interval 500


### Disabling Events
You can disable events by commenting them out in the ADV_EVENTS and FORT_EVENTS tables in the code. 

### Adding New Events
If you decide to create functions for new events, you'll add them to the appropriate table (ADV_EVENTS or FORT_EVENTS) and they should start occurring.

### Automatic Running
If you want this mod to run automatically without having to call it in the DFHack console, add **random-event start [ticks]** to the **onLoad.init** file inside of **dfhack-config\init**.

***
## Random Pregnancy
If you need a random pregnancy to occur enter **random-pregnancy**.

***
## Set Book Title
While examining a book's description enter **set-book-title -both "New Book Title"** to change the book's title.

<img width="640" height="360" alt="1" src="https://github.com/user-attachments/assets/f0a633aa-3f2e-4682-9ea8-ae092c83e436" />
<img width="640" height="360" alt="2" src="https://github.com/user-attachments/assets/812da6f7-b7c8-447c-80a1-85dbe76083b0" />


# Use cases (J2) — draft for review

The jobs people come to Hexmap to do, each as a short story: who, where
they start, where they end, what must be true, and the fewest steps it
should take. They are the test the UI refactor (J3, J4) is held to: each
becomes an end-to-end test that drives the real windows, and a playtest
script.

The steps are what the person *does*; how the screen gets them there is
J3's job. A step count is a ceiling, not a target.

## Who

- **The DM** runs the game from a laptop or desktop: the Table.
- **A player** plays from a phone (or a laptop): the Player.
- **An author** makes adventures for other DMs: a DM using the export.
- **A mapmaker** draws maps: the Editor.

## U1 — Run a downloaded adventure, session one

*A DM downloaded "The Ruined Chapel" and has four friends coming over.*

- **Starts:** the app just installed, the package in Downloads.
- **Ends:** the party is on the forest road, on everyone's phones, each
  player with a character; the session has started.
- **Must be true:** nothing needs installing; the DM never sees a file
  format, a licence wall before the pitch, or a network address unless
  something went wrong; the adventure's own notes tell the DM what to do
  first.
- **Steps (DM):** open Hexmap → *Play an adventure* → pick the file (or
  it is already offered) → read the pitch, *Start* → the map is up and
  players are told how to join → *Start the session* when everyone has
  a character. **≤ 5.**
- **Steps (player):** open Hexmap on the phone → *Join a game* → the
  DM's table is the one offered → pick a name → make a character
  (or take the one the DM made). **≤ 5.**

## U2 — Run a fight

*The party reaches the chapel.*

- **Starts:** the road on screen, a session running.
- **Ends:** the fight in the chapel is over, the party back on the road
  with their wounds.
- **Must be true:** the DM starts it *from the map* (the chapel on the
  road); everything that matters in a fight — who is in it, whose turn,
  who is hidden, a creature's stat block, a reveal — is on one screen;
  players see their turn and their options on the phone; getting back
  is one action.
- **Steps (DM):** click the chapel on the road → *Run this encounter* →
  reveal as the party sees → roll initiative → run turns → *End the
  fight*. **≤ 6 besides the turns themselves.**

## U3 — Pick up where we left off

*A week later, same group.*

- **Starts:** the app opened.
- **Ends:** the campaign open where it was, phones back in, session two
  started.
- **Must be true:** the last campaign is the first thing offered; the
  phones find it again without typing; last session's state — wounds,
  the clock, where the party is — is there; a recap is at hand.
- **Steps (DM):** open Hexmap → *Continue "Our Chapel"* → *Start
  session 2*. **≤ 3.**

## U4 — Prep between sessions

*The DM has an evening and wants next week's content ready.*

- **Starts:** the campaign open, no session running, no players.
- **Ends:** a new fight prepared on a new map, an NPC added, a handout
  written, a supplement's monsters imported, a class turned off.
- **Must be true:** prep does not look like running a game (no turn
  order, no "players online"); each job is found where a DM would look
  (the map for fights and places, the cast for NPCs, notes for notes, a
  library for content).
- **Steps:** each job ≤ 4 from the campaign's main screen.

## U5 — Build a campaign from scratch

*A DM with their own world and their own maps.*

- **Starts:** the app, a folder of maps from the Editor, a ruleset
  installed.
- **Ends:** a campaign with a regional map, two places, a prepared fight,
  the party's characters.
- **Must be true:** "which rules" is asked once, up front, in words
  ("D&D 5E (SRD, 2024)"), not as a plugin id; adding a map is adding a
  place in the world, not a scene.
- **Steps:** *New campaign* → name, rules → add maps → mark places →
  prepare a fight. Each ≤ 3.

## U6 — A player joins mid-game, or rejoins

*A player's phone died; another turns up late.*

- **Starts:** a session running.
- **Ends:** both are back in with their characters.
- **Must be true:** the phone offers the table it was at; a late player
  can join and make or be given a character without stopping the table;
  the DM sees who is in.
- **Steps (player):** open Hexmap → *Rejoin "Our Chapel"*. **≤ 2.**

## U7 — Make and share an adventure

*An author turns their campaign into a package for others.*

- **Starts:** a campaign they have built and played.
- **Ends:** a `.campaignpkg` a stranger can start (U1), and next month a
  1.1 that DMs already playing it are offered.
- **Must be true:** the author writes the pitch the DM will read first
  (U1); what is theirs and what is borrowed is listed with its licence;
  the party's play is never in it.
- **Steps:** *Share as an adventure* → pitch, version → save. **≤ 3.**

## U8 — Draw a map

*A mapmaker in the Editor.* Out of scope for this refactor: the Editor
works and the playtest was about the Table. It stays reachable from Home
and from the Table's map library ("Edit this map").

## U9 — A session of talk and exploring, no fight

*Most sessions never reach a fight* (the user, after J1/J2). The party
arrives in a village, talks to people, asks around, travels on.

- **Starts:** the campaign open, a session running, the region on screen.
- **Ends:** the party knows what they came to learn and is on the road.
- **Must be true:** the party's sheets and the region are on screen; any
  person, place, note or rule is one search away; a person's card has
  what the DM knows and the DCs to learn it; a social roll (of the
  party, one character, or a person of the world; open or secret) is two
  clicks from the screen the DM is on.
- **Steps (DM):** click a place → read it out → *Show the players* → ask
  for a roll → look something up. **Each ≤ 2.**

## U10 — Show the players something

*A picture of the village, the innkeeper's face, the reeve's notice.*

- **Starts:** the thing open in the Reference pane.
- **Ends:** it is on the players' phones (all, or the one it is for), and
  in their Journal after.
- **Must be true:** the DM chooses who sees it and can take it back; the
  DM's notes never go with it; the card says who has seen it.
- **Steps (DM):** *Show the players ▾* → everyone, or one of them. **≤ 2.**

## Questions for review

1. **Are these the right jobs?** Anything missing (e.g. running a game
   with no map at all — theatre of the mind; a DM on a single screen
   with no phones; a co-DM)? *Answered: U9 and U10 were missing — most
   sessions are talk and looking things up, and showing players things is
   constant.*
2. **U1 and U3 put "play an adventure" and "continue" on Home**, above
   Editor / Table / Player. Is that the right first screen, or should
   Home stay a mode picker?
3. **Prep vs play (U4 vs U2)**: should the Table have two distinct modes
   the DM switches between, or one screen that adapts to "session
   running / fight running"? *Built: three modes — World (the default),
   Fight (entered and left with a fight), Prep.*
4. **The players' side (U1, U6)**: should joining ever show a network
   list, or only "the table on this network" plus a code to type?

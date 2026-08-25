# Coffee Hunter: Grounds for Adventure

A quick coffee-break game, built in Godot 4.7.2.

## The Story

Paolo Jones is a coffee connoisseur of some renown. After decades of caffeine
dependency — and a number of strictly private tours of the plantations behind his
favourite roasts — he stumbled upon an uncomfortable truth: only about 5% of all
coffee beans actually carry that wonderful, addictive aroma.

Worse, roasting spreads the aroma from those few beans to every bean next to them,
smearing it thinly across the entire batch. And since beans are roasted right after
the harvest, buying coffee and sorting out the good beans afterwards is impossible.

So Paolo went to the plantations himself, to pick the beans that cannot be bought.

### The Guards

The special beans are watched by a hand-picked troop, selected by the plantation
owners for a single qualification: they would never help themselves to a coffee bean.
They are, to a man, hopelessly caffeine-dependent **tea** drinkers — recognisable by
an enormous, wildly oversized teapot that usually hides both the face and the body of
whoever is carrying it.

The teapot is oversized on purpose: the tea must never run out, so the guards can
watch the plantation all day without walking back to the tea kitchen, or — far worse —
being tempted by the coffee. Happily for Paolo, a teapot that size also ruins your
field of view, and an intruder is very hard to make out from behind one.

### The Filters

Day after day Paolo works his way through the rows, hunting for the good beans and
keeping an eye out for the guards. Once a plantation is picked clean, he moves on to
the next one.

By now the fields are littered with used coffee filters, dropped wherever someone
brewed a quick cup. Paolo has to watch his step: coffee grounds on freshly picked
beans have to be cleaned off immediately, or the beans lose their aroma.

### The Owner

Paolo cannot afford to take his time, either. Linger too long on a plantation and the
owner turns up, charging at him like an enraged ape. The owner carries no teapot — he
sees Paolo perfectly well. The only way out is to strip the field fast and run for the
next plantation.

## Run

```sh
godot --editor project.godot
godot --path .
```

Controls: WASD or arrow keys. Hold and drag the left mouse button to simulate device tilt. Press `R` to restart.

Standing still for five seconds brews a coffee; `F` (or `Ctrl`) throws it. It
flies two cells along your facing, stops at undug soil, and scalds the tea-pod it
hits for the same 200 points a dropped filter pays. Walking spills a half-brewed
mug, but a full one keeps until it is thrown.

Type your name into the field at the bottom of the title screen. It is remembered
between sessions, it labels you in a network race, and it is what stands next to
your score in the high-score table — the five best single-player runs, shown on
the title screen. Match scores stay out of that table: they include points stolen
off a rival and would not compare.

## Plantations (network match)

Press `N` on the title screen for a race of **two to four** players. Every
plantation is grown from one shared seed, so all boards are identical and the
race is fair. Each board carries a portal — the turning blue ring — and the
portals form a ring of their own: stepping into one drops you on the *next*
plantation, and a full lap brings you home. Beans you pick while raiding count
for *your* score, and a shoved coffee filter is as lethal to a player as it is to
a tea-pod.

Standing still for five seconds brews a coffee; `F` (or `Ctrl`) throws it, which
the side panel spells out during a match. Walking spills a half-brewed mug, but a
full one keeps until it is thrown. It flies two cells along your facing, stops at
undug soil, and a hit takes half the rival's score and one life. A portal hop
banks two thirds of the brew, so raiding arrives nearly armed. Stolen points
never buy extra lives — only beans you picked yourself count toward those.

The side panel lists every player in their own colour, the same colour their
figure wears on the board, with score, lives and whether they are standing on the
board you are looking at.

Run out of lives and you are **out**: your figure leaves the board and you watch
the rest of the race from where you fell. The others carry on, and whoever is
still standing when everybody else is out wins — survival beats scoring. Only a
match that runs its full `MATCH_LEVELS` is settled on points. Someone who loses
their connection is dropped the same way, so a quitter cannot end anyone else's
race.

The end screen offers a rematch that takes *everybody*: each player presses
SPACE, the screen names who is still missing, and the host starts the next race on
a fresh seed once the last one agrees. Seats left empty by quitters are closed up
first. ESC leaves for the title and drops the link.

### Connecting

The host is found automatically on the local network — press `H` to host, then
pick the game from the list with a number key; the list shows how full each game
is. Typing an address works too: click the field first, since a focused field
swallows the shortcuts. That is what covers `127.0.0.1` for a local test and a
Tailscale/ZeroTier address for playing over the internet without port forwarding
or a relay.

Joining puts you in a waiting room that lists everyone present. Nobody drops into
a race unannounced: the host presses SPACE when the room is as full as it is going
to get, from two players upward.

Two instances on one machine do not see each other in the list — both would need
the same discovery port — so join the second one by typing `127.0.0.1`.

The host owns the simulation and ships each guest only the one plantation that
guest is standing on. Four whole boards would not fit in a single ENet packet, and
a client never draws the others anyway.

The level runs continuously: enemies and falling filters use independent realtime clocks instead of advancing only when the player moves.

On macOS the game opens at 1440x810 by default while retaining its 960x540 internal canvas.

## Verify

```sh
godot --headless --path . --script tests/run_tests.gd
godot --headless --path . --editor --quit
godot --headless --path . --export-release macOS "build/Coffee Hunter.app"
```

Generated project assets and their final prompts are documented in `docs/art/asset-prompts.md`.
The first macOS size measurement is recorded in `docs/build-baseline.md`.

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

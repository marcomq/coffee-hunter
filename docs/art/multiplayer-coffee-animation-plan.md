# Multiplayer coffee animation plan

The generated source art is now connected to the multiplayer presentation in
`scripts/main.gd`. The existing authoritative charge, throw, hit, and network
timing remains unchanged.

## Source sheets

- `hero-coffee-charge-sheet-v1.png`: 4 columns x 4 rows. Rows face down, up,
  left, and right; columns progress from cup-and-pot ready to a filled steaming
  cup.
- `hero-coffee-throw-sheet-v1.png`: 4 columns x 4 rows in the same direction
  order. Columns are anticipation, wind-up, release, and follow-through.
- `coffee-cup-flight-sheet-v1.png`: optional cup presentation. The top row
  contains four directional views; the bottom row contains four rotation phases.

These are high-resolution generation sources. They still need deterministic
cell cropping, downscaling with nearest-neighbour sampling, and visual cleanup
before becoming runtime sprites.

## Implemented integration

1. Runtime presentation
   - Godot selects equal four-by-four regions directly from the two hero sheets
     and scales them to the existing 52-pixel actor footprint.
   - The generated source files remain untouched.

2. Replace the charge ring
   - Map the existing charge ratio to the four pour frames: 0-24%, 25-49%,
     50-74%, and 75-99%.
   - At 100%, hold the filled-cup/steam frame. Avoid looping so the effect remains
     subtle.
   - Cancel immediately back to the normal directional idle when a partial charge
     spills through movement.

3. Animate the throw
   - Play the four action frames once over roughly 180-240 ms.
   - Spawn the projectile on the release frame, not at animation start.
   - Keep authoritative hit timing and network state unchanged; the animation is
     presentation only.

4. Coffee presentation
   - The charge circle remains available as a dormant fallback node, while the
     pouring pose is now the default.
   - A cropped transparent mug from the throw release frame travels to the same
     final free cell as the authoritative throw scan.

## Verification checklist

- Charging, spilling, full charge, throwing, portal travel, and remote-player
  playback still follow existing match timing.
- Both player tints remain distinguishable on every animation frame.
- The projectile appears exactly on the release frame and travels the same cells
  as before.
- At native game resolution, the cup is readable without drawing more attention
  than enemies, beans, or hazards.
- No runtime code should depend on the irregular dimensions of the generated
  source sheets.

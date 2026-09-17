# Direct Hit

Battleships, except every hit is a real ship taking a real shell.

Call a square, and if something is under it the board steps aside: a camera drops
to the water beside the vessel you just found, the round comes in, and you watch
the hull take it. The ship in the cutscene is the ship you hit, the hole is where
along her length you hit her, and if that was the last square she had left, she
goes down while you watch.

Built in Godot 4.7. Five real hulls - a Ford-class carrier, the Littorio, a
Ticonderoga, a nuclear submarine and an Arleigh Burke destroyer - on a Gerstner
sea, all in real time.

## Playing

Two modes: against the computer, or pass-the-device for two people.

## Running it

    /Applications/Godot.app/Contents/MacOS/Godot --path .

## Checking it

The rules are checked without drawing anything:

    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/checks/_rules.tscn --quit-after 2000

The cutscene is checked by photographing it, because a ship sailing backwards has
the same bounding box as one sailing forwards:

    /Applications/Godot.app/Contents/MacOS/Godot --path . res://dev/looks/_cutscene.tscn --quit-after 4000

Pictures land in `dev/shots/`, which git ignores - they are output, not source.

## The project record

The whole record of this game - idea, decisions, methods, session log and every
screenshot - is one self-contained HTML file at `docs/index.html`, generated
from the knowledge base:

    python3 tools/docs/build_docs.py

Run the look scenes first; `dev/shots/` is git-ignored, so a fresh clone has no
pictures to embed. The published copy lives at a private artifact link recorded
at the top of that script, and is republished to the same URL so the link never
changes.

## Credit

Every hull came from Sketchfab under CC Attribution and must be credited. Each
model's `ATTRIBUTION.md` sits beside it in `assets/sketchfab/`, and `CREDITS.md`
collects them.

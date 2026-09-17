# Direct Hit

Battleships, fought from the bridge of a battleship.

There is no chart on a screen. You stand on the bridge of the Littorio with your
own fleet in formation around you - a carrier, a cruiser, a destroyer and a
submarine - and you fight from there. Beside you is a lit plotting table with the
enemy's stretch of sea on it; that is where you lay your own fleet out before the
action and where you call a target once it starts. Then you put your eye to the
director sight, lay the guns on the bearing it gives you, and fire.

If the round finds something, the camera goes to it: the vessel you hit, taking
that shell at the point along her hull where you actually hit her, and going down
if that was her last square. Afterwards she stays on your horizon, burning.

When they fire back you do not read about it. You are standing on the ship they
are shooting at.

Built in Godot 4.7. One unit is one metre, five real hulls on a Gerstner sea, and
everything within arm's reach of the player built in code - because a model meant
to be seen from half a mile away does not survive being stood on.

## Playing

| key | what it does |
|---|---|
| mouse | look around the bridge |
| T | the plotting table, and back |
| SPACE | the gun sight; fire when the guns are on |
| ESC | back to the bridge |

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

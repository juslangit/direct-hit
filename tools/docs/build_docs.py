#!/usr/bin/env python3
"""Builds docs/index.html: the whole record of Direct Hit in one file.

Every game of Luqman's keeps one living HTML record - the idea, the planning,
every decision and method, the session logs, and the screenshots with their
explanations - held in the repo and published as a website whose link never
changes. This is the generator: the project notes stay the source of truth and
the page is rebuilt from them.

    python3 tools/docs/build_docs.py
    python3 tools/docs/build_docs.py --publish                # and rebuild the local records site

SITE: ~/Documents/dev/docs-site/direct-hit/index.html   (open it with `docs-site open`)
Run `docs-site publish` after building to put the new page there.

The machinery here - the markdown converter, the image embedding, the page
template - was ported from referee-for-fun's build_docs.py, which is the
original. Only the data tables below and the page layout are this game's own.

Reads:
    ~/.claude/knowledge/projects/direct-hit/*.md and log/*.md   (override: KNOWLEDGE=...)
    dev/shots/*.png                                            (the galleries below)
    docs/record/*                                              (committed: today's screens, history, diagrams, check output)
    dev/checks/*.gd, dev/looks/*.gd                            (their ## headers)
    git log

Writes docs/index.html, fully self-contained: every screenshot is embedded as a
JPEG. No packages beyond the standard library; `sips`, built into macOS, does
the shrinking.

Screenshots come from the look scenes and are git-ignored, so run those first:

    G=/Applications/Godot.app/Contents/MacOS/Godot
    $G --path . res://dev/looks/_hulls.tscn    --quit-after 3000
    $G --path . res://dev/looks/_cutscene.tscn --quit-after 4000
    $G --path . res://dev/looks/_screens.tscn  --quit-after 3000
"""

import base64
import datetime
import html
import os
import pathlib
import re
import subprocess
import tempfile

PROJECT = pathlib.Path(__file__).resolve().parents[2]
KNOWLEDGE = pathlib.Path(os.environ.get(
    "KNOWLEDGE", pathlib.Path.home() / ".claude/knowledge/projects/direct-hit"))
OUT = PROJECT / "docs" / "index.html"
SITE = pathlib.Path.home() / "Documents/dev/docs-site/direct-hit/index.html"   # the built page on this machine
SHOTS = PROJECT / "dev" / "shots"
IMAGE_WIDTH = 880
IMAGE_QUALITY = 62

missing = []
_cache = pathlib.Path(tempfile.gettempdir()) / "direct-hit-docs-images"
_cache.mkdir(exist_ok=True)


GALLERIES = [
    ("screens-start", "From the menu to putting to sea", "Everything before the first shot, photographed on 2026-09-30 from the game as it stands. The fleet is laid out on the same plotting table that later carries the enemy's water, so by the time the battle starts the player already knows where the table is and how it reads.", [
        ("docs/record/menu.jpg", "The main menu today: the oil-painting key art on the right, the title and three buttons in the clear space on the left. The picture was chosen over a poster version because its bow keeps out of the text column."),
        ("docs/record/place-turned.jpg", "Laying the carrier up and down the plot. The green ghost is five squares long and legal where it is; the line under the chart says which ship, how long she is and which way she is lying."),
        ("docs/record/place-illegal.jpg", "The same ghost pushed off the edge: at 7 in row I a five-square ship would run off the chart, so the squares turn orange and a click there does nothing."),
        ("docs/record/place-partial.jpg", "Three ships down, drawn as grey hulls on the paper, and the submarine's ghost waiting in row H. PUT TO SEA stays dark until the whole fleet is laid."),
        ("docs/record/place-ready.jpg", "After SCATTER THEM: all five ships placed at random, the line reads 'The fleet is at sea.' and PUT TO SEA lights up."),
    ]),
    ("screens-turn", "One turn, start to finish", "A single turn against the computer, photographed step by step on 2026-09-30: look out, call a square, lay the guns, fire, watch where it lands, then take the reply. The captions follow the order a player meets these screens.", [
        ("docs/record/watch-start.jpg", "The first thing seen after putting to sea: the three forward windows, your own foredeck and turrets, wrecks already burning on the horizon, and the instruction 'Find them. T for the plotting table.'"),
        ("docs/record/sight-laid.jpg", "Eye to the gun sight with square C3 called. The readout on the left gives bearing RED 034, range 6686 metres and ON TARGET - FIRE. The wheelhouse pillar fills the left third of the view, because the sight sits inside the room."),
        ("docs/record/guns-fire.jpg", "SPACE pressed: the forward turrets have fired and a cloud of brown gun smoke rolls back across the window."),
        ("docs/record/shell-in-flight.jpg", "A second later, turned towards the enemy's bearing: the smoke has drifted aft across the windows while the shell spends 2.6 seconds in the air."),
        ("docs/record/their-turn.jpg", "A miss means no cutscene - the message is 'Nothing there. Just water.' - and then the computer shoots back: 'They have our range.'"),
        ("docs/record/cut-banner-hit.jpg", "A hit. The picture cuts to a close view of the ship you hit - here the battleship at F3 - with HIT and the square written over it. The fire is on the part of the hull that sits in the square you called."),
        ("docs/record/found-burning.jpg", "Back on the bridge afterwards: 'Your shot. T for the plotting table.' A ship you have found stays on the horizon, burning, as the only record of your hits outside the chart."),
        ("docs/record/sight-burning.jpg", "Through the sight on a ship already hit: the carrier at F5 sits under the designator with smoke rising from her deck, 6486 metres away."),
        ("docs/record/cut-banner-sunk.jpg", "The last square of the battleship: SUNK, in a deeper red than HIT. She is rolling towards the hole and settling while the camera stays well off her beam."),
        ("docs/record/plot-midgame.jpg", "The plot part-way through: misses as small circles (A1, B8, C3), hits as orange bursts, the sunk battleship across F3 to F6. The table's front grab handles sit over the corner squares in row J from this viewpoint."),
    ]),
    ("screens-ending", "Pausing and ending", "ESC always reaches the pause screen, because once the battle starts the bridge takes the mouse pointer and a player with no way to get it back is trapped. A match ends on the bridge, not on a separate screen.", [
        ("docs/record/pause.jpg", "STAND EASY: the pause screen over the plot, listing every key, with CARRY ON, BACK TO PORT and LEAVE THE SHIP. The pale scrim lets the chart show through behind the text."),
        ("docs/record/victory.jpg", "VICTORY, drawn over the windows with the shots, hits and accuracy under it (79% in this run), and SAIL AGAIN or BACK TO PORT. The grey detail line is hard to read against the bright sea."),
        ("docs/record/defeat.jpg", "The other ending: YOUR FLEET IS GONE, in the same place and the same brass as a win."),
    ]),
    ("screens-two", "Two players, one device", "In a two-player game the device is handed across after every placement and every shot. The handover screen is solid, not see-through, because anything behind it would show the other player's fleet.", [
        ("docs/record/pvp-place.jpg", "Player 1 lays out: the same table and bar as against the computer, with 'Player 1 -' in front of the instruction."),
        ("docs/record/handover.jpg", "PASS THE DEVICE: 'Player 2 lays her fleet out next.' and one button, I AM READY. Player 1's ships are only a faint trace under the paper-coloured cover."),
        ("docs/record/pvp-place-p2.jpg", "Player 2 then lays out on a clean chart of their own."),
    ]),
    ("screens-bridge", "Inside the wheelhouse", "The player stands in an enclosed steel wheelhouse mounted where the Littorio's own bridge was: a deck underfoot, four bulkheads, a deckhead overhead, a band of windows forward and one each side, and the fittings a bridge actually has. It is all built in code, because a hull model bought for use at half a mile does not survive being stood in. What the bought hull provides is everything beyond the windows - the foredeck and the turrets - which is the distance it is good at. An earlier version put the player on an open platform on top of the ship, which read as standing on the roof.", [
        ("br_ahead", "Forward through the window band: mullions, the sill with its grab rail, the deckhead, and your own foredeck held inside the frame. How far back the player stands is the whole difference between a room and a window pressed against your face."),
        ("br_the_wheel", "Turning round: the wheel on its pedestal, an engine telegraph either side, the doorway aft, and the plotting table to port."),
        ("ui_menu", "The title screen is the game: the wheelhouse, under way, with your escorts on the beams."),
        ("ui_war_horizon", "Somebody else's battle: wrecks burning across the bows, aircraft going over, gunfire on the horizon."),
    ]),
    ("screens-table", "The plotting table", "A lit glass plot on the bridge, carrying the same chart the flat version of the game used - rendered into a viewport and used as the table's own surface, so one piece of code decides what a hit, a miss and a sunk ship look like. The fleet is laid out on it before the action and targets are called on it afterwards, so the player has already used the table once before it starts mattering.", [
        ("ui_placement", "Laying the fleet out: the ghost of the carrier on the plot, five squares, legal where it is."),
        ("ui_battle_plot", "In action, the table carries the enemy's water instead: misses as flat discs, hits as bursts, the called square in brass."),
        ("br_plot_table", "The table itself, inside the wheelhouse, with a voice pipe beyond it and the sea through the side window."),
        ("br_aft_quarter", "The wheelhouse from its after corner: the wheel on the left, the plotting table on its pedestal, the deckhead lamp, and the long window band down the side."),
        ("br_port_window", "Looking to port from beside the wheel: the plotting table in the corner and the side windows running forward, with an escort on the horizon."),
    ]),
    ("screens-sight", "The gun sight", "The bearing ribbon is the piece that matters. The plot gives a square, the square gives a bearing, and the ribbon is how the guns get onto it - which is the job a director sight actually did. The first version of this screen laid a lit grid on the enemy's water instead; see the note in Methods for why that could never have worked.", [
        ("ui_battle_sight", "Eye to the director at eight and a half degrees: the bearing ribbon with the guns and the target nearly together, the elevation ladder, and the designator sitting on the square that was called."),
        ("br_sight", "Laid on, and free to fire."),
    ]),
    ("screens-underway", "Under way", "Three things that separate a fleet action from a diorama, all added on 2026-09-18. Her guns train on the square you called - the Littorio is a bought model with her turrets welded on, so both forward turrets are cut out of the merged meshes at load time and hung on nodes that can rotate. Every ship leaves a wake, drawn as a strip of mesh displaced by the same Gerstner waves as the sea it lies on. And the wrecks on the horizon burn in proper columns; for three attempts they came out as dark balls, and the cause was particle turbulence, which carries particles along with it rather than merely shaking them.", [
        ("gun_fore_and_aft", "Fore and aft, where she sits before a square has been called. Two superfiring triple turrets, both welded solid in the file this hull came out of."),
        ("gun_trained_34", "Trained on the enemy's bearing, thirty-four degrees to starboard. Both gunhouses have stayed on their barbettes and the deck around them is whole, which is what the cut has to get right."),
        ("gun_trained_90", "Hard over, which is the worst case for the cut: anything taken out of the hull by mistake is now thirty metres from where it belongs."),
        ("wake_astern", "Her own wake from astern, running unbroken from under the stern and riding the swell. The foam pattern scrolls aft at exactly her own speed, so it stands still in the water while the strip carrying it moves with her."),
        ("wake_from_the_beam", "And from the beam at sea level, which is how the player sees an escort's."),
        ("wreck_column", "A wreck three kilometres off the starboard bow, with a cruiser of your own between you and her. Eight hundred metres of smoke, against the hundred-metre ball this was for three attempts."),
        ("column_variants", "How the smoke problem was found: four copies of the same column side by side, each with one setting changed. Three stay as dark balls; the one with turbulence switched off rises as a column."),
        ("wreck_horizon", "Two wrecks burning at different distances, as seen from the bridge with the controls bar along the bottom."),
        ("who_owns_from_above", "Which part of the hull belongs to which turret, from above: every piece of the merged model coloured by the gun it was assigned to before the turrets were cut free."),
        ("who_owns_the_guns", "The same colouring from the side. Anything painted the wrong colour here would have swung round with the wrong turret."),
        ("cut_trained_above", "After the cut, from above: the first turret (red) and the second (blue) lifted out of the hull and trained, with the deck under them left whole."),
        ("cut_trained_beam", "The same two turrets from the beam, trained out, sitting on their barbettes at the right height."),
        ("gun_from_above", "Looking straight down from the bridge onto the superfiring turret and the wooden deck in front of it."),
    ]),
    ("screens-fleet", "The fleet", "Five real vessels, pulled from Sketchfab under CC Attribution and normalised at load rather than edited. One unit is one metre, and at sixty metres to a grid square four of the five come out within a few per cent of their real lengths. These are the photographs that caught the submarine sailing stern-first, and later every one of them riding with her main deck under water.", [
        ("carrier_side", "Carrier - five squares, 300 m. Gerald R. Ford class."),
        ("battleship_side", "Battleship - four squares, 240 m. The Littorio, which is the ship the player stands on."),
        ("cruiser_side", "Cruiser - three squares, 180 m. Ticonderoga class."),
        ("submarine_side", "Submarine - three squares. Photographed stern-first at first: a bounding box cannot tell you which end is the bow, but the propeller in a render can."),
        ("destroyer_side", "Destroyer - two squares. Arleigh Burke class."),
        ("battleship_bow", "Close on the bow, which is where too much draft shows first."),
        ("carrier_bow", "The carrier from low on her bow, riding at her real draft with the flight deck overhanging the sea."),
        ("carrier_top", "Carrier from directly above, on a dark background: the check that her flight deck runs the right way and that she is five squares long."),
        ("battleship_top", "Battleship from above - long and narrow, bow to the left like every hull in the game."),
        ("cruiser_top", "Cruiser from above: three squares."),
        ("submarine_top", "Submarine from above: the propeller end on the right, which is how the stern-first mistake was caught."),
        ("destroyer_top", "Destroyer from above: two squares, the smallest hull the cutscene camera has to frame."),
    ]),
    ("how-it-works", "How it works", "Four diagrams drawn for this record on 2026-09-30 from the code, so the game can be explained without reading it. They are rendered from mermaid text with mermaid-cli.", [
        ("docs/record/diagram-turn.png", "One turn. Everything in the game hangs off the middle diamond: the rules answer miss, hit, sunk or fleet gone, and the bridge and the cutscene only stage that answer."),
        ("docs/record/diagram-screens.png", "The screens and how a player moves between them, including the PASS THE DEVICE screen that appears after every shot in a two-player game."),
        ("docs/record/diagram-parts.png", "How the scripts fit together. main.gd decides which screen is up; the rules (board.gd, ship.gd, match_state.gd) never draw anything; the cutscene is told only which ship, which segment and whether she sank."),
        ("docs/record/diagram-checks.png", "What each check and look scene tests. The checks end in a verdict; the looks save pictures for a person to judge."),
    ], "wide"),
    ("history", "How it changed", "The game at six points in its history. Each older commit was checked out on its own, run, and photographed with the look scene that existed at that commit - these are the real old versions, not reconstructions.", [
        ("docs/record/history-2026-09-17-first-cutscene.jpg", "2026-09-17, commit 16d2ddd - the first thing built, before any board existed: the rules, five real hulls, and the hit cutscene. The Littorio taking a shell amidships on a dark blue sea."),
        ("docs/record/history-2026-09-17-flat-menu.jpg", "2026-09-17, commit 9e07d47 - the first playable game. The title sat over a live sea with a cruiser steaming through it, and two buttons."),
        ("docs/record/history-2026-09-17-flat-board.jpg", "The same day's board: a flat two-grid Battleships screen, your waters on the left, enemy waters on the right, and a list of ships under each."),
        ("docs/record/history-2026-09-17-flat-cutscene-banner.jpg", "The same version's cutscene with its HIT banner and a 'click to skip' note - the cutscene has barely changed since; everything around it has."),
        ("docs/record/history-2026-09-17-bridge-menu.jpg", "2026-09-17, commit 39ad542 - the whole game moved onto the bridge of a battleship. The title was drawn straight over the view from an open platform, with the rail across the bottom."),
        ("docs/record/history-2026-09-17-open-bridge.jpg", "The open-platform bridge in action: standing on top of the ship behind a rail, with the smoke columns still drawn as black balls."),
        ("docs/record/history-2026-09-17-open-bridge-table.jpg", "Its plotting table: a blue glass grid lying almost flat and seen at a steep angle, with the letters down the side too foreshortened to read."),
        ("docs/record/history-2026-09-17-first-wheelhouse.jpg", "2026-09-17, commit b53633d - the player is put inside a wheelhouse: window frames, a sill and a brass rail, which is the room the game still uses."),
        ("docs/record/history-2026-09-18-real-main-menu.jpg", "2026-09-18, commit 1d6af03 - a real main menu: the text column on the left with LEAVE THE SHIP added, over a live shot of a ship being hit."),
        ("docs/record/history-2026-09-18-sky-over-the-wheelhouse.jpg", "The same commit on the bridge: the message now sits in a dark band across the top, and ESC pause has joined the controls along the bottom - the way out of a captured pointer."),
        ("docs/record/history-2026-09-18-glass-plot.jpg", "The plot as blue glass, turned to face the reader - with a white blob in the middle that was the deckhead lamp reflected in a shiny surface."),
        ("docs/record/history-2026-09-18-paper-plot.jpg", "2026-09-18, commit 7edd86d - the plot became chart paper with generated art. Making the paper rough (0.92) is what removed the lamp's reflection."),
    ]),
    ("checks-running", "The checks, running", "The four main checks run on 2026-09-30 and their real output. The rules and asset checks run headless; the flow and play checks need a window because they build real screens and push real input through them.", [
        ("docs/record/checks-rules.png", "_rules: placement, shots and sinking, then 300 full games by the computer gunner - every game finished, the worst took 69 shots and the average was 52.5, which proves it neither cheats nor flounders."),
        ("docs/record/checks-flow.png", "_flow: a match driven from the menu to the last ship through the real screens - including that the enemy fleet is never drawn on your plot and that the handover hides the bridge completely."),
        ("docs/record/checks-play.png", "_play: real key presses and clicks through the whole input system. Everything passed except the battle frame rate - 22 fps at full Retina size on this run, with many other programs busy on the same Mac, against 61 fps at the menu."),
        ("docs/record/checks-assets.png", "_assets: every hull, sound, shader and the sky load, the sun is aimed at the sun painted into the sky, and all five CC-BY hulls are credited."),
    ], "wide"),
]


# Each beat of the cutscene, photographed. The seconds are counted from the
# moment the board steps aside.
CUTSCENES = [
    ("cut-hit", "A hit she survives", "about three and a half seconds", [
        ("cut_hit_0p35", "0.35 s", "Opening wide and low, quartering from ahead. She is already under way before the player sees her."),
        ("cut_hit_0p80", "0.80 s", "The round is in the air, arcing down from off the bow."),
        ("cut_hit_1p10", "1.10 s", "Impact, at the point along her hull that the player actually called."),
        ("cut_hit_1p35", "1.35 s", "Fire out of the hole, debris up, the flash still on the water."),
        ("cut_hit_2p10", "2.10 s", "She leans away from the blow and keeps going."),
        ("cut_hit_3p60", "3.60 s", "Pulling back with the smoke still climbing, which is what makes a hit feel like it did damage."),
    ]),
    ("cut-sunk", "A hit that finishes her", "about seven and a half seconds", [
        ("cut_sunk_1p10", "1.10 s", "The last square she had left."),
        ("cut_sunk_2p40", "2.40 s", "Rolling toward the hole, steam where hot steel meets the sea."),
        ("cut_sunk_4p00", "4.00 s", "Settling: the deck awash."),
        ("cut_sunk_5p60", "5.60 s", "Going under."),
        ("cut_sunk_7p20", "7.20 s", "Only smoke left. The camera stands well off for a sinking - hung on the hull instead, it followed her under, which is how the first one was filmed from inside the wreck."),
    ]),
    ("cut-small", "The same shot on the smallest hull", "the framing has to hold at a quarter the length", [
        ("cut_small_1p10", "1.10 s", "A destroyer taking one on the bow. Every camera mark is written as a fraction of the hull's own length, so the framing holds from a 52-unit destroyer to a 130-unit carrier."),
        ("cut_small_1p60", "1.60 s", "Half a second later."),
    ]),
]


NOTES = [
    ("idea", "Idea", "01-idea.md", None),
    ("planning", "Planning", "02-planning.md", 2),
    ("milestones", "Milestones", "03-milestones.md", 2),
    ("decisions", "Decisions", "06-decisions.md", 2),
    ("methods", "Methods", "04-methods.md", 2),
    ("relations", "Relations", "05-relations.md", None),
    ("references", "References", "07-references.md", 2),
]


# --- markdown ------------------------------------------------------------------------------

def inline(text):
    """The inline half of markdown, on already-escaped text."""
    codes = []

    def keep(m):
        codes.append(m.group(1))
        return f"\x00{len(codes) - 1}\x00"

    text = re.sub(r"`([^`]+)`", keep, text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)",
                  lambda m: f'<a href="{m.group(2)}">{m.group(1)}</a>'
                  if m.group(2).startswith(("http://", "https://")) else m.group(1), text)
    text = re.sub(r"(?<![\w&])(https?://[^\s<)]+)", r'<a href="\1">\1</a>', text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"~~(.+?)~~", r"<del>\1</del>", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?!\w)", r"<em>\1</em>", text)
    text = re.sub(r"(?<![\w])_(?!\s)(.+?)(?<!\s)_(?![\w])", r"<em>\1</em>", text)
    return re.sub(r"\x00(\d+)\x00", lambda m: f"<code>{codes[int(m.group(1))]}</code>", text)


def slug(text, taken):
    base = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:60] or "section"
    name, n = base, 2
    while name in taken:
        name, n = f"{base}-{n}", n + 1
    taken.add(name)
    return name


def markdown(source, prefix, taken, fold=None, drop_title=True):
    """Converts one notes file. Headings at `fold` open a <details> that holds everything
    until the next heading at that level or above."""
    source = re.sub(r"\A---\n.*?\n---\n", "", source, flags=re.S)
    lines = source.split("\n")
    out, para, lists, open_folds = [], [], [], 0
    i = 0

    def flush_para():
        if para:
            out.append("<p>" + inline(html.escape(" ".join(para), quote=False)) + "</p>")
            para.clear()

    def close_lists(to=0):
        while len(lists) > to:
            out.append(f"</{lists.pop()[0]}>")

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped.startswith("```"):
            flush_para(); close_lists()
            block = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                block.append(lines[i])
                i += 1
            out.append("<pre><code>" + html.escape("\n".join(block)) + "</code></pre>")
            i += 1
            continue

        heading = re.match(r"^(#{1,4})\s+(.*)$", line)
        if heading:
            flush_para(); close_lists()
            level = len(heading.group(1))
            title = heading.group(2).strip()
            if level == 1 and drop_title:
                i += 1
                continue
            if fold is not None and level <= fold:
                while open_folds:
                    out.append("</div></details>")
                    open_folds -= 1
            anchor = slug(f"{prefix}-{title}", taken)
            if fold is not None and level == fold:
                out.append(f'<details class="fold" id="{anchor}"><summary><span>'
                           f"{inline(html.escape(title, quote=False))}</span></summary><div>")
                open_folds += 1
            else:
                tag = min(level + 1, 5)
                out.append(f'<h{tag} id="{anchor}">{inline(html.escape(title, quote=False))}</h{tag}>')
            i += 1
            continue

        if stripped.startswith("|") and i + 1 < len(lines) and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            flush_para(); close_lists()
            def cells(row):
                return [c.strip() for c in row.strip().strip("|").split("|")]
            head = cells(line)
            i += 2
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(cells(lines[i]))
                i += 1
            out.append('<div class="table"><table><thead><tr>' + "".join(
                f"<th>{inline(html.escape(c, quote=False))}</th>" for c in head) + "</tr></thead><tbody>")
            for row in rows:
                out.append("<tr>" + "".join(
                    f"<td>{inline(html.escape(c, quote=False))}</td>" for c in row) + "</tr>")
            out.append("</tbody></table></div>")
            continue

        item = re.match(r"^(\s*)([-*]|\d+\.)\s+(\[[ xX]\]\s+)?(.*)$", line)
        if item:
            flush_para()
            depth = len(item.group(1)) // 2
            kind = "ol" if item.group(2)[0].isdigit() else "ul"
            while len(lists) > depth + 1:
                out.append(f"</{lists.pop()[0]}>")
            if len(lists) == depth + 1 and lists[-1][0] != kind:
                out.append(f"</{lists.pop()[0]}>")
            if len(lists) < depth + 1:
                out.append(f"<{kind}>")
                lists.append((kind, depth))
            box = item.group(3)
            mark = ""
            if box:
                mark = '<span class="box done">done</span> ' if "x" in box.lower() else '<span class="box">to do</span> '
            text = item.group(4)
            # A continuation line indented under the item belongs to it.
            while i + 1 < len(lines) and lines[i + 1].startswith(" " * (len(item.group(1)) + 2)) \
                    and lines[i + 1].strip() and not lines[i + 1].strip().startswith("|") \
                    and not re.match(r"^\s*([-*]|\d+\.)\s+", lines[i + 1]):
                i += 1
                text += " " + lines[i].strip()
            out.append(f"<li>{mark}{inline(html.escape(text, quote=False))}</li>")
            i += 1
            continue

        if stripped.startswith(">"):
            flush_para(); close_lists()
            quote = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                quote.append(lines[i].strip()[1:].strip())
                i += 1
            out.append("<blockquote>" + inline(html.escape(" ".join(quote), quote=False)) + "</blockquote>")
            continue

        if re.match(r"^\s*(---|\*\*\*)\s*$", line):
            flush_para(); close_lists()
            i += 1
            continue

        if not stripped:
            flush_para()
            if not (i + 1 < len(lines) and re.match(r"^\s+([-*]|\d+\.)\s+", lines[i + 1])):
                close_lists()
            i += 1
            continue

        if lists and line.startswith("  ") and not stripped.startswith("|"):
            # Loose text under a list item.
            out[-1] = out[-1].replace("</li>", " " + inline(html.escape(stripped, quote=False)) + "</li>")
            i += 1
            continue

        close_lists()
        para.append(stripped)
        i += 1

    flush_para(); close_lists()
    while open_folds:
        out.append("</div></details>")
        open_folds -= 1
    return "\n".join(out)


# --- pictures ----------------------------------------------------------------------------

_cache = pathlib.Path(tempfile.gettempdir()) / "direct-hit-docs-images"
_cache.mkdir(exist_ok=True)
missing = []


def picture(name, width=IMAGE_WIDTH):
    """(data URI, date) for a screenshot, or (None, None) when it is not there."""
    path = PROJECT / name if "/" in name else SHOTS / f"{name}.png"
    if not path.exists():
        missing.append(name)
        return None, None
    stamp = int(path.stat().st_mtime)
    jpeg = _cache / f"{path.stem}-{stamp}-{width}.jpg"
    if not jpeg.exists():
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(IMAGE_QUALITY),
                        "-Z", str(width), str(path), "--out", str(jpeg)],
                       check=True, capture_output=True)
    data = base64.b64encode(jpeg.read_bytes()).decode()
    return f"data:image/jpeg;base64,{data}", datetime.date.fromtimestamp(stamp).isoformat()


def figure(name, caption, label="", width=IMAGE_WIDTH):
    uri, date = picture(name, width)
    if uri is None:
        return (f'<figure class="shot missing"><div class="gap">Screenshot not taken yet: '
                f"<code>{html.escape(name)}</code></div><figcaption>{html.escape(caption)}</figcaption></figure>")
    stamp = f'<span class="tc">{html.escape(label)}</span>' if label else ""
    return (f'<figure class="shot"><img src="{uri}" alt="{html.escape(caption)}" loading="lazy" '
            f'width="{IMAGE_WIDTH}" height="{IMAGE_WIDTH * 9 // 16}"><figcaption>{stamp}'
            f'<span>{html.escape(caption)}</span><span class="date">{date}</span></figcaption></figure>')


def grid(figures, wide=False):
    if wide:
        return f'<div class="shots single">{"".join(figures)}</div>'
    return f'<div class="shots{" odd" if len(figures) % 2 else ""}">{"".join(figures)}</div>'


# --- the facts that can be counted ---------------------------------------------------------

def git(*args):
    return subprocess.run(["git", *args], cwd=PROJECT, capture_output=True, text=True).stdout


def counts():
    return [
        ("Ships", "5"),
        ("Scripts", str(len(list((PROJECT / "scripts").glob("*.gd"))))),
        ("Checks", str(len(list((PROJECT / "dev" / "checks").glob("*.gd"))))),
        ("Looks", str(len(list((PROJECT / "dev" / "looks").glob("*.gd"))))),
        ("Commits", git("rev-list", "--count", "HEAD").strip()),
        ("Decisions", str(len(re.findall(r"^## ", (KNOWLEDGE / "06-decisions.md").read_text(), re.M)))),
    ]


def header_comment(path):
    lines = []
    for line in path.read_text().split("\n"):
        if line.startswith("##"):
            text = line[2:].strip()
            if not text and lines:
                break
            if text:
                lines.append(text)
        elif lines:
            break
    return " ".join(lines)


def catalogue(folder):
    rows = []
    for path in sorted((PROJECT / "dev" / folder).glob("*.gd")):
        rows.append(f"<tr><td><code>{path.stem}</code></td>"
                    f"<td>{inline(html.escape(header_comment(path) or '—', quote=False))}</td></tr>")
    return '<div class="table"><table><thead><tr><th>Scene</th><th>What it asks</th></tr></thead><tbody>' \
        + "".join(rows) + "</tbody></table></div>"


def history():
    rows = []
    for line in git("log", "--date=short", "--pretty=format:%h\t%ad\t%s").split("\n"):
        if not line:
            continue
        sha, date, subject = line.split("\t", 2)
        merge = " merge" if subject.lower().startswith("merge") else ""
        rows.append(f'<tr class="{merge.strip()}"><td><code>{sha}</code></td><td class="nowrap">{date}</td>'
                    f"<td>{html.escape(subject)}</td></tr>")
    return '<div class="table"><table><thead><tr><th>Commit</th><th>Date</th><th>Change</th></tr></thead><tbody>' \
        + "".join(rows) + "</tbody></table></div>"


# --- the page ----------------------------------------------------------------------------------

PIPELINE = [
    ("Ask", "Where the cutscenes come from, what to build it in, who the player plays against - put to Luqman before a line was written.", "01-idea.md, 06-decisions.md"),
    ("Rules first", "The board, the fleet and the computer gunner, proven with nothing drawn.", "scripts/board.gd, dev/checks/_rules.gd"),
    ("Hulls", "Five models downloaded from Sketchfab, measured, and corrected in a table rather than edited.", "scripts/ship_models.gd"),
    ("Stage it", "Ocean, sky, camera, shell, fire and smoke - all generated from the result of the shot.", "scripts/cutscene.gd"),
    ("The bridge", "The whole game moved onto a battleship: a wheelhouse built in code, a plotting table, a gun sight and turrets cut free so they can train.", "scripts/bridge.gd, wheelhouse.gd, turret.gd"),
    ("Sky and art", "A CC0 photographed sky with the sun aimed to match it, and interface art generated once and then corrected by hand.", "assets/, 04-methods.md"),
    ("Look", "Photographs at exact beats, read back and judged by eye.", "dev/looks/, dev/shots/"),
    ("Check", "Scenes that end in a verdict - the rules, the real screens, real keys and clicks, and every asset.", "dev/checks/"),
    ("Play and review", "Luqman plays and reports back; the notes record what was decided.", "log/, 06-decisions.md"),
    ("Record", "This page, rebuilt from the notes, the look pictures, docs/record/ and git.", "tools/docs/build_docs.py"),
]

TOOLS = [
    ("Godot 4.7.2", "Engine. Everything is built in code, including the board and the cutscene, so every camera mark and explosion timing reads in one file."),
    ("GDScript", "All game logic, the rules apart from the staging."),
    ("Sketchfab", "All five hulls and the aircraft, CC Attribution, normalised at load by ship_models.gd and credited in the game."),
    ("Poly Haven", "The sky: kloofendal_38d, a CC0 photographed panorama. Its sun is 37.8 degrees up, and the game's light is aimed there."),
    ("OpenArt", "Generated the key art, the steel, the brass and the chart paper once, on 2026-09-18; every image was cropped or corrected by hand before it went in."),
    ("sfx (Freesound)", "CC0 sound only, with every file's source recorded in assets/audio/freesound/SOURCES.md."),
    ("ffmpeg", "One conversion: this build of Godot has no FLAC importer and drops the file without saying so."),
    ("mermaid-cli and git worktree", "For this record: the How it works diagrams are drawn from text, and the How it changed pictures come from old commits checked out beside the real folder."),
    ("Knowledge base", "The project notes this page is built from, kept outside the repo."),
]


def page():
    taken = set()
    overview = (KNOWLEDGE / "00-overview.md").read_text()
    thesis = re.search(r"^# direct-hit — Overview\n\n(.+?)(?=\n\n)", overview, re.S | re.M)
    thesis = " ".join(l.strip() for l in thesis.group(1).split("\n")) if thesis else ""
    built = datetime.date.today().isoformat()

    toc, body = [], []

    # Cover
    stats = "".join(f'<div class="stat"><b>{v}</b><span>{k}</span></div>' for k, v in counts())
    uri, _ = picture("cut_hit_1p10")
    hero = (f'<img class="hero" src="{uri}" alt="A battleship taking a shell amidships on open ocean" '
            f'width="{IMAGE_WIDTH}" height="495">') if uri else ""
    body.append(f'''
<header class="cover" id="top">
  <p class="eyebrow"><b>Direct Hit</b><span>Project record · built {built}</span></p>
  <h1>Direct Hit</h1>
  <p class="thesis">{inline(html.escape(thesis, quote=False))}</p>
  <div class="stats">{stats}</div>
  {hero}
</header>''')

    # Pipeline
    toc.append(("pipeline", "Pipeline", []))
    steps = "".join(f'<li><b>{html.escape(a)}</b><span>{html.escape(b)}</span><code>{html.escape(c)}</code></li>'
                    for a, b, c in PIPELINE)
    tools = "".join(f"<tr><td><strong>{html.escape(a)}</strong></td><td>{html.escape(b)}</td></tr>" for a, b in TOOLS)
    body.append(f'''
<section class="chapter" id="pipeline">
  <p class="kicker">How the game got made</p>
  <h2>Pipeline</h2>
  <p class="lede">The rules were built and proven before anything was drawn, because everything visible is generated from one dictionary the rules hand over: which ship, how far along her hull, and whether she went down. If the cutscene ever disagrees with the board, the board is right.</p>
  <ol class="pipeline">{steps}</ol>
  <h3 id="tools">Tools</h3>
  <div class="table"><table><tbody>{tools}</tbody></table></div>
</section>''')

    # Screens
    subs, parts = [], []
    for gid, title, intro, shots, *layout in GALLERIES:
        # A gallery marked "wide" shows one picture to a row at twice the size: diagrams
        # and terminal output are unreadable at half the page width.
        wide = "wide" in layout
        size = IMAGE_WIDTH * 2 if wide else IMAGE_WIDTH
        subs.append((gid, title))
        parts.append(f'<section class="gallery" id="{gid}"><h3>{html.escape(title)}</h3>'
                     f'<p class="note">{html.escape(intro)}</p>'
                     f'{grid([figure(n, c, width=size) for n, c in shots], wide)}</section>')
    toc.append(("screens", "Screens", subs))
    body.append(f'''
<section class="chapter" id="screens">
  <p class="kicker">What the player sees</p>
  <h2>Screens</h2>
  <p class="lede">Every screenshot on this page was taken by a scene that drives the game from outside and saves a frame, because the questions that matter here are visual ones. A ship sailing backwards has exactly the same bounding box as one sailing forwards.</p>
  {"".join(parts)}
</section>''')

    # The cutscene, beat by beat
    subs, parts = [], []
    for cid, title, length, frames in CUTSCENES:
        subs.append((cid, title))
        parts.append(f'''<section class="gallery" id="{cid}">
  <h3>{html.escape(title)} <span class="status">{html.escape(length)}</span></h3>
  {grid([figure(n, c, label) for n, label, c in frames])}
</section>''')
    toc.append(("cutscenes", "The cutscene", subs))
    body.append(f'''
<section class="chapter" id="cutscenes">
  <p class="kicker">The moment the whole game exists for</p>
  <h2>The cutscene</h2>
  <p class="lede">Not a clip. The sea, the ship, the shell and the fire are generated live from the shot that was just scored, which is the only way the vessel on screen can be the vessel you hit and the hole can be where you hit her. A clip cannot know either. Any click skips it.</p>
  {"".join(parts)}
</section>''')

    # The notes
    for nid, title, name, fold in NOTES:
        path = KNOWLEDGE / name
        if not path.exists():
            continue
        text = path.read_text()
        converted = markdown(text, nid, taken, fold)
        heads = [h for h in re.findall(r"^## (.+)$", re.sub(r"```.*?```", "", text, flags=re.S), re.M)]
        folds = ' <button class="unfold" type="button" data-for="%s">Open all</button>' % nid if fold else ""
        toc.append((nid, title, []))
        body.append(f'''
<section class="chapter notes" id="{nid}">
  <p class="kicker">{html.escape(name)} · {len(heads)} sections{folds}</p>
  <h2>{html.escape(title)}</h2>
  <div class="prose">{converted}</div>
</section>''')

    # Logs
    logs = sorted((p for p in (KNOWLEDGE / "log").glob("*.md") if not p.name.startswith("_")), reverse=True)
    entries = "".join(
        f'<details class="fold" id="log-{p.stem}"><summary><span>{p.stem}</span></summary>'
        f'<div>{markdown(p.read_text(), "log-" + p.stem, taken, None)}</div></details>'
        for p in logs)
    toc.append(("log", "Session log", []))
    body.append(f'''
<section class="chapter notes" id="log">
  <p class="kicker">log/ · {len(logs)} sessions <button class="unfold" type="button" data-for="log">Open all</button></p>
  <h2>Session log</h2>
  <div class="prose">{entries}</div>
</section>''')

    # Catalogues
    toc.append(("checks", "Checks and looks", []))
    body.append(f'''
<section class="chapter" id="checks">
  <p class="kicker">dev/checks and dev/looks, from each scene\'s own header</p>
  <h2>Checks and looks</h2>
  <p class="lede">A check runs and ends in a verdict. A look takes screenshots for a person to judge. Both are scenes under <code>res://dev/</code>. Between them they caught a submarine sailing stern-first, a fireball burning in mid-air, particles bigger than the ship, a camera that followed a sinking vessel under the water, and the computer\'s own fleet appearing face up on the player\'s chart.</p>
  <details class="fold"><summary><span>Checks</span></summary><div>{catalogue("checks")}</div></details>
  <details class="fold"><summary><span>Looks</span></summary><div>{catalogue("looks")}</div></details>
</section>''')
    toc.append(("history", "Git history", []))
    body.append(f'''
<section class="chapter" id="history">
  <p class="kicker">git log, newest first</p>
  <h2>Git history</h2>
  <details class="fold"><summary><span>Every commit</span></summary><div>{history()}</div></details>
</section>''')

    nav = []
    for tid, title, subs in toc:
        inner = "".join(f'<li><a href="#{sid}">{html.escape(st)}</a></li>' for sid, st in subs)
        nav.append(f'<li><a href="#{tid}">{html.escape(title)}</a>{f"<ul>{inner}</ul>" if inner else ""}</li>')

    return TEMPLATE.replace("{{NAV}}", "".join(nav)).replace("{{BODY}}", "".join(body))


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Direct Hit Record</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@600;700&family=IBM+Plex+Mono:wght@500&family=IBM+Plex+Sans:ital,wght@0,400;0,500;0,600;1,400&display=swap">
<style>
:root {
  --ground: #FAF7F2; --surface: #FFFFFF; --ink: #2B2622; --muted: #6B6259; --line: #E7E1D8;
  --court: #2F6BB0; --court-soft: #D6E6FA; --caption: #FFEEC9; --caption-ink: #A97B12;
  --done: #2F7A5C; --display: "Barlow Condensed", "Arial Narrow", "Helvetica Neue", Arial, sans-serif;
  --body: "IBM Plex Sans", "Helvetica Neue", Arial, sans-serif; --mono: "IBM Plex Mono", ui-monospace, Menlo, monospace;
  color-scheme: light;
}
@media (prefers-color-scheme: light) {
  :root:not([data-theme="light"]) { --ground: #FAF7F2; --surface: #FFFFFF; --ink: #2B2622; --muted: #6B6259;
    --line: #E7E1D8; --court: #2F6BB0; --court-soft: #D6E6FA; --done: #2F7A5C; color-scheme: light; }
}
:root[data-theme="dark"] { --ground: #FAF7F2; --surface: #FFFFFF; --ink: #2B2622; --muted: #6B6259;
  --line: #E7E1D8; --court: #2F6BB0; --court-soft: #D6E6FA; --done: #2F7A5C; color-scheme: light; }
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
@media (prefers-reduced-motion: reduce) { html { scroll-behavior: auto; } }
body { margin: 0; background: var(--ground); color: var(--ink); font: 400 16px/1.6 var(--body); padding-inline: 20px; }
a { color: var(--court); }
a:focus-visible, button:focus-visible, summary:focus-visible { outline: 2px solid var(--court); outline-offset: 2px; }
.layout { max-width: 1320px; margin: 0 auto; display: grid; grid-template-columns: 220px minmax(0, 1fr); gap: 48px; padding-block: 32px 96px; }
nav.toc { position: sticky; top: calc(env(safe-area-inset-top, 0px) + 20px); align-self: start; max-height: calc(100vh - 40px); overflow-y: auto; font-size: 14px; }
nav.toc > ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 4px; }
nav.toc > ul > li > a { font: 700 16px/1.3 var(--display); letter-spacing: .06em; text-transform: uppercase; color: var(--ink); text-decoration: none; }
nav.toc ul ul { list-style: none; margin: 2px 0 8px; padding: 0 0 0 10px; border-left: 1px solid var(--line); display: grid; gap: 1px; }
nav.toc ul ul a { color: var(--muted); text-decoration: none; }
nav.toc a:hover { color: var(--court); }
main { display: grid; gap: 72px; min-width: 0; }
.eyebrow { display: inline-flex; gap: 10px; align-items: center; margin: 0; font: 700 14px/1 var(--display); letter-spacing: .12em; text-transform: uppercase; }
.eyebrow b { background: var(--caption); color: var(--caption-ink); padding: 5px 9px; }
.eyebrow span { color: var(--muted); }
h1 { font: 700 clamp(44px, 7vw, 84px)/.92 var(--display); text-transform: uppercase; margin: 14px 0 12px; text-wrap: balance; }
.thesis { max-width: 68ch; margin: 0; font-size: 18px; }
.stats { display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 0; margin: 28px 0; border-block: 2px solid var(--ink); }
.stat { padding: 12px 14px; display: grid; gap: 2px; border-left: 1px solid var(--line); }
.stat:first-child { border-left: 0; padding-left: 0; }
.stat b { font: 700 34px/1 var(--display); font-variant-numeric: tabular-nums; }
.stat span { font-size: 12px; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); }
.hero { width: 100%; max-width: 100%; height: auto; display: block; }
.chapter { display: grid; gap: 14px; scroll-margin-top: 16px; }
.kicker { margin: 0; font-size: 13px; color: var(--muted); display: flex; flex-wrap: wrap; gap: 12px; align-items: center; }
h2 { font: 700 48px/1 var(--display); text-transform: uppercase; margin: 0 0 6px; padding-bottom: 10px; border-bottom: 2px solid var(--ink); }
h3 { font: 700 30px/1.05 var(--display); text-transform: uppercase; margin: 24px 0 4px; scroll-margin-top: 16px; }
h4 { font: 700 21px/1.1 var(--display); text-transform: uppercase; letter-spacing: .02em; margin: 18px 0 8px; }
h4 small { font: 400 14px var(--body); text-transform: none; color: var(--muted); margin-left: 8px; }
h5 { font: 600 16px/1.3 var(--body); margin: 18px 0 4px; }
.lede, .note { max-width: 70ch; margin: 0; color: var(--muted); }
.gallery { scroll-margin-top: 16px; display: grid; gap: 8px; }
.status { font: 500 12px/1 var(--mono); text-transform: none; letter-spacing: 0; color: var(--court); background: var(--court-soft); padding: 4px 8px; vertical-align: middle; }
.shots { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 18px; margin-top: 10px; }
.shots.odd > .shot:first-child { grid-column: 1 / -1; }
.shots.single { grid-template-columns: 1fr; }
.shots.odd > .shot:first-child img { max-height: 520px; object-fit: cover; }
.shot { margin: 0; display: grid; gap: 6px; align-content: start; }
.shot img { display: block; width: 100%; max-width: 100%; height: auto; background: var(--line); }
.shot figcaption { font-size: 14px; line-height: 1.4; display: grid; grid-template-columns: auto 1fr auto; gap: 10px; align-items: baseline; }
.tc, .date { font: 500 12px/1 var(--mono); color: var(--muted); white-space: nowrap; font-variant-numeric: tabular-nums; }
.missing .gap { aspect-ratio: 16 / 9; display: grid; place-items: center; border: 1px dashed var(--line); color: var(--muted); font-size: 14px; padding: 16px; text-align: center; }
.rules { list-style: none; margin: 8px 0 0; padding: 0; display: grid; gap: 6px; max-width: 80ch; }
.rules li { display: grid; grid-template-columns: 92px 1fr; gap: 12px; font-size: 14.5px; }
.ref { font: 500 12px/1.7 var(--mono); color: var(--court); background: var(--court-soft); text-align: center; align-self: start; }
.pipeline { list-style: none; counter-reset: step; margin: 10px 0 0; padding: 0; display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 0; border-top: 1px solid var(--line); border-left: 1px solid var(--line); }
.pipeline li { counter-increment: step; padding: 14px 16px 16px; display: grid; gap: 4px; align-content: start; border-right: 1px solid var(--line); border-bottom: 1px solid var(--line); background: var(--surface); }
.pipeline b { font: 700 20px/1 var(--display); text-transform: uppercase; }
.pipeline b::before { content: counter(step) "  "; color: var(--court); font-family: var(--mono); font-size: 13px; font-weight: 500; }
.pipeline span { font-size: 14.5px; }
.pipeline code { font-size: 12px; color: var(--muted); justify-self: start; }
.prose { max-width: 82ch; display: grid; gap: 0; }
.prose p, .prose ul, .prose ol, .prose blockquote, .prose pre, .prose .table { margin: 0 0 12px; }
.prose ul, .prose ol { padding-left: 22px; }
.prose li { margin: 3px 0; }
.prose blockquote { border-left: 3px solid var(--caption); padding: 4px 0 4px 14px; color: var(--muted); }
code { font: 500 .86em var(--mono); background: var(--court-soft); padding: 1px 4px; overflow-wrap: anywhere; }
pre { background: var(--surface); border: 1px solid var(--line); padding: 12px 14px; overflow-x: auto; }
pre code { background: none; padding: 0; overflow-wrap: normal; white-space: pre; }
.table { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; font-size: 14px; }
th, td { text-align: left; vertical-align: top; padding: 7px 10px; border-bottom: 1px solid var(--line); }
th { font: 700 14px/1.2 var(--display); letter-spacing: .08em; text-transform: uppercase; color: var(--muted); border-bottom: 2px solid var(--ink); }
.chapter > .table td:first-child { width: 220px; }
tr.merge td { color: var(--muted); }
.nowrap { white-space: nowrap; font-variant-numeric: tabular-nums; }
del { color: var(--muted); }
.box { font: 500 11px/1 var(--mono); padding: 2px 5px; border: 1px solid var(--line); color: var(--muted); vertical-align: 1px; }
.box.done { color: var(--done); border-color: var(--done); }
details.fold { border-bottom: 1px solid var(--line); scroll-margin-top: 16px; }
details.fold > summary { cursor: pointer; list-style: none; padding: 10px 0; display: flex; gap: 10px; align-items: baseline; font: 600 16px/1.35 var(--body); }
details.fold > summary::-webkit-details-marker { display: none; }
details.fold > summary::before { content: "+"; font: 500 14px var(--mono); color: var(--court); width: 12px; flex: none; }
details.fold[open] > summary::before { content: "\\2212"; }
details.fold > div { padding: 2px 0 18px 22px; }
.unfold { font: 600 12px/1 var(--body); color: var(--court); background: var(--surface); border: 1px solid var(--line); padding: 5px 9px; cursor: pointer; }
.unfold:hover { border-color: var(--court); }
@media (max-width: 980px) {
  .layout { grid-template-columns: 1fr; gap: 24px; }
  nav.toc { position: static; max-height: none; border-bottom: 2px solid var(--ink); padding-bottom: 14px; }
  nav.toc > ul { grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); }
  nav.toc ul ul { display: none; }
  .stats { grid-template-columns: repeat(3, minmax(0, 1fr)); }
  .stat:nth-child(4) { border-left: 0; padding-left: 0; }
  .pipeline { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}
@media (max-width: 560px) {
  .shots { grid-template-columns: 1fr; }
  .pipeline { grid-template-columns: 1fr; }
  h2 { font-size: 38px; }
  .rules li { grid-template-columns: 1fr; gap: 2px; }
  .ref { justify-self: start; padding: 0 6px; }
  .shot figcaption { grid-template-columns: 1fr; gap: 2px; }
}
</style>
</head>
<body>
<div class="layout">
  <nav class="toc" aria-label="Contents"><ul>{{NAV}}</ul></nav>
  <main>{{BODY}}</main>
</div>
<script>
document.querySelectorAll(".unfold").forEach(function (button) {
  button.addEventListener("click", function () {
    var section = document.getElementById(button.dataset.for);
    var folds = section.querySelectorAll("details.fold");
    var opening = button.textContent === "Open all";
    folds.forEach(function (d) { d.open = opening; });
    button.textContent = opening ? "Close all" : "Open all";
  });
});
// A link to something inside a closed fold opens the fold.
function openTarget() {
  var target = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1)));
  for (var node = target; node; node = node.parentElement) {
    if (node.tagName === "DETAILS") node.open = true;
  }
  if (target) target.scrollIntoView();
}
window.addEventListener("hashchange", openTarget);
openTarget();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    import sys
    OUT.parent.mkdir(exist_ok=True)
    document = page()
    OUT.write_text(document)
    if "--publish" in sys.argv:
        subprocess.run(["docs-site", "publish"], check=True)
    size = OUT.stat().st_size / 1024 / 1024
    print(f"wrote {OUT.relative_to(PROJECT)}  ({size:.1f} MB)")
    if missing:
        print("screenshots not found (shown as gaps):", ", ".join(missing))

class_name Palette
extends RefCounted

## One place for every colour in the game, so the board, the fleet list and the
## banners cannot drift apart. The scheme is a naval plotting chart: deep blue
## paper, pale ruled lines, brass for anything the player owns and a hot orange
## that appears only where a shell has landed.

const PAPER := Color("0a1620")
const PANEL := Color("112637")
const PANEL_EDGE := Color("1d4359")
const RULE := Color("23536e")
const RULE_FAINT := Color("18384b")
const WATER := Color("0d2a3d")
const INK := Color("cfe2ee")
const INK_DIM := Color("7b97a8")
const BRASS := Color("c9a227")
const BRASS_DIM := Color("7d661a")
const STEEL := Color("64798a")
const STEEL_DARK := Color("3f5261")
const HIT := Color("e2562c")
const HIT_GLOW := Color("ff8a4c")
const SUNK := Color("8e2116")
const MISS := Color("9fb8c8")
const GOOD := Color("4fb286")

## The plotting table is aged chart paper now rather than a lit blue screen, so
## everything drawn on it is ink and pencil instead of glowing lines.
const PAPER_SHEET := Color("efe3cc")
const PAPER_INK := Color("2e2418")
const PAPER_INK_SOFT := Color("6b5a40")
const PAPER_RULE := Color("8a7757")
const PAPER_RULE_FAINT := Color("9d8a68")
const PAPER_PENCIL := Color("5a5648")

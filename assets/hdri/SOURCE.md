# Sky

`kloofendal_38d_partly_cloudy_puresky_4k.hdr`

| | |
|---|---|
| Source | Poly Haven — https://polyhaven.com/a/kloofendal_38d_partly_cloudy_puresky |
| Licence | CC0 — public domain, no attribution required, safe to sell |
| Size | 4K equirectangular, 20 MB |
| Got with | `polyhaven get kloofendal_38d_partly_cloudy_puresky -r 4k` |

A "puresky" has no ground in it, only sky down to the horizon, which is what an
ocean scene wants: the sea is the ground, and a baked-in landscape would show
through the water at the horizon.

**The sun in the game is aimed at the sun in this image.** If the HDRI is ever
swapped, re-run `dev/checks/_sunangle.tscn`, which finds the brightest point in
the panorama and prints the direction to it - otherwise the shadows on the ships
fall one way while the sky says the light comes from another.

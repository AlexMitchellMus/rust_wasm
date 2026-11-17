# rustc.wasm artwork

- `icon.svg`: colour icon, transparent background.
- `icon-silhouette-white.svg`: one-colour version for dark backgrounds (bits: 1 = solid, 0 = 25%).
- `icon-silhouette-black.svg`: one-colour version for light backgrounds.

A sphere throws off two spiral tails that break into droplets of data; solid droplets are 1s, faint ones 0s.
Regenerate all three with `python3 tools/make_icon.py` (no dependencies beyond Python 3).

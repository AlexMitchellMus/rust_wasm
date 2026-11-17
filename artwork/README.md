# rustc.wasm artwork

- `icon.svg`: colour icon, transparent background.
- `icon-silhouette-white.svg`: one-colour version for dark backgrounds (bits: 1 = solid, 0 = 25%).
- `icon-silhouette-black.svg`: one-colour version for light backgrounds.

A sphere throws off two tapered swirl tails (exact curves leaving the sphere tangentially) that release droplets of data; solid droplets are 1s, faint ones 0s.
Regenerate all three with `python3 tools/make_icon.py` (no dependencies beyond Python 3).

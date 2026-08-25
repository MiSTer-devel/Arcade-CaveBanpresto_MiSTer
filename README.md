# Cave 68000 Banpresto/Gazelle

This is a fork of Nullobject's [Cave68000 core](https://github.com/MiSTer-devel/Arcade-Cave_MiSTer) focused on supporting the Banpresto and Gazelle games. This core was split from the main core for timing and space reasons, but the majority of the code is still Nullobject's. Big thanks to them for all the hard work they put into the original core!

## Supported Games

| Title | Status | Notes |
|-------|--------|-------|
| Air Gallet | Public | |
| Hotdog Storm | WIP | MAME-based. No hardware-accurate comparison made |
| Mazinger Z | Public | |
| Metamoqester | WIP | MAME-based. No hardware-accurate comparison made |
| Pretty Soldier Sailor Moon | Public | |

## Layout

- `rtl/` contains the active HDL. `rtl/cave/` is the hand-maintained Cave core.
- `rtl/modules/ikaopm/` contains the pinned IKAOPM YM2151 implementation.
- `sys/` is the MiSTer framework drop-in.
- `mra/` contains the active MRA files for the supported games.
- `cfg/` and `nvram/` contain the MiSTer config/NVRAM defaults used by those
  MRAs.
- `releases/` carries the release-side copies of the active MRAs.

## Build

Build the core with Quartus:

```sh
make build
```

Program a DE10-Nano from the Quartus machine:

```sh
make program
```

## License

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

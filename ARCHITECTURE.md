# Architecture

The project is organized by responsibility:

- `source/core/` - General systems without concrete world objects.
- `source/world/` - Playfield and game objects.
- `source/data/` - Level and configuration data.
- `source/ui/` - Rendering, camera, menus, and transitions.
- `source/sounds/` - Audio resources.
- `source/images/` - Image resources.
- `tools/` - External development tools.

File responsibilities:

- `source/main.lua` - Playdate entry point.
- `source/core/config.lua` - Project configuration.
- `source/pdxinfo` - Playdate package metadata.
- Core modules - Shared geometry, state, undo, and audio systems.
- World modules - Ring, shutter, bridge, switch, gate, player, and room objects.
- `source/data/levels.lua` - Level data.
- UI modules - Camera, rendering, menu, and transition concerns.
- `tools/solver.py` - Future offline solver and level validator.
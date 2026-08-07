# Ringe project rules

- Target platform: Panic Playdate.
- Use Lua and Playdate SDK APIs.
- Target resolution is 400x240 pixels with 1-bit graphics.
- Respect the existing module structure and avoid large architectural changes without justification.
- Do not add dependencies unless necessary.
- Keep game state and rendering separated where practical.
- Do not invent mechanics that are not in the specification.
- Verify changes with a build or tests when possible.
- Never claim successful tests that were not actually run.
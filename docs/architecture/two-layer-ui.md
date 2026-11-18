# Two-layer UI and genre reuse

Status: local first version, 2026-11-18. The genre ZIP has not been remotely published.

```text
Independent game
  ├── base Defold Library: framework/
  └── optional tycoon Defold Library: game_modules/tycoon/
           └── imports framework/ui/components/
```

`framework/` holds lifecycle, navigation, save, platform, audio and GUI primitives usable by any genre. `game_modules/` holds optional genre APIs and editable GUI templates. `examples/` demonstrates those APIs; its game-specific scenes, names, and assets are not exported in either library. A type template, when added, will be a copied independent project referencing these libraries.

Version semantics: `scripts/export-libraries.py` reads the framework version from the latest `vX.Y.Z` git tag (this directory when it is a git checkout, else a sibling `defold-game-framework` checkout; `--framework-version`/`--tycoon-version` override). A ZIP named `defold-framework-X.Y.Z.zip` therefore matches GitHub tag `vX.Y.Z` content; `manifest.json` records the file name and SHA-256, and `check-layers.py` reads names from that manifest instead of hardcoding them. Stale archives from older versions are removed on export.

The root development project exports both `framework game_modules` so it can run examples. `scripts/export-libraries.py` produces separate ZIP Library Projects with distinct versions and `include_dirs` for consumers. `scripts/check-layers.py` copies the miner example into an isolated temporary consumer, serves the two ZIPs plus SHA-256-checked upstream dependencies, and attempts a build with no local `framework/` or `game_modules/` source directory. Resource compilation reached the engine stage, but the independent build is not yet green: the remote Defold Extender TLS handshake failed. Retry when that service is reachable. On a clean machine, publish the ZIPs at immutable version URLs and list both in the consumer's `game.project`; Defold library dependencies do not automatically install the other library or its upstream dependencies.

Current tycoon slice: currency header GUI template and binding, upgrade row binding. Mining, worker names and prices stay in the example. Future tycoon components should be extracted only after a second game needs the same composition. A platformer or simulation kit gets its own folder and versioned ZIP, depending on `framework` but never on `tycoon`.

Scope still open: create a complete `template-tycoon` copyable project, extract shared shop/upgrade GUI layouts after a second consumer confirms their node contract, and validate the ZIP pair in a real second game. The first version demonstrates independent packaging and a real GUI template; it does not yet claim full tycoon template coverage.

[Defold GUI template nodes](https://defold.com/manuals/gui-template/) document the prefix behavior and the fact that GUI template scripts are not instantiated.

Verification: root Bob resource build passed; the root engine started the miner view from the new archive with no Lua errors; Lua unit suite passed including the two new tycoon UI cases. The isolated consumer downloaded both layer ZIPs (`defold-framework-1.1.0.zip`, `defold-tycoon-ui-0.1.0.zip`), compiled all Lua and resources, then failed only at remote engine compilation due to the SSL handshake with Defold Extender. Retry when that service is reachable. See `logs/layers-consumer-build.log` locally.

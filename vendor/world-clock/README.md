# Serpantinum World Clock

A native Quickshell world-clock module for Serpantinum 2.1.0. The collapsed
bar item shows a globe and local time. Its popup renders a smoothly rotating,
sun-lit 3D Earth with saved city markers and DST-aware local times.

## Privacy

Clock refreshes are entirely local. City search uses a bundled major-city and
IANA timezone catalogue first. If no local match exists and **Online search**
is enabled, the typed query is sent directly to Open-Meteo's geocoding API.
No weather requests are made.

## Development

```sh
nix develop
cargo test
nix flake check
```

The Nix integration exports `lib.patchSerpantinum`, which is applied to an
existing Serpantinum package derivation. It verifies the pinned 2.1.0 source
shape before modifying package-output QML.

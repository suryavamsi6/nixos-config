# Third-party notices

## Omarchy World Clock data and timezone-grid decoder

`data/featured-cities.json`, `data/timezone-grid.bin`, and the initial version
of `src/timezone_grid.rs` were obtained from
[olivoil/omarchy-world-clock](https://github.com/olivoil/omarchy-world-clock),
Copyright (c) 2026 Olivier Melcher. The source code is MIT licensed. The
complete ODbL 1.0 text for the derived timezone grid is shipped as
`data/ODbL-1.0.txt`.

The featured-city catalogue is derived from Natural Earth 5.1.2 Populated
Places. Natural Earth data is public domain. The timezone grid is derived from
`tzf-rel` 0.0.2026-a and is distributed under the Open Database License 1.0;
individual contents may be subject to the Database Contents License. See
`data/UPSTREAM-DATA.md` for upstream provenance.

## NASA Earth imagery

The bundled globe textures are NASA imagery. NASA makes these Earth-science
images freely available for reuse unless an image carries a specific copyright
notice. Credit: NASA Goddard Space Flight Center / Scientific Visualization
Studio / Visible Earth.

- `assets/earth-day.jpg`: NASA SVS 3615, “Equirectangular Projected Earth for
  LARGEST”, cloud-free 2048×1024 image.
  <https://svs.gsfc.nasa.gov/3615/>
  SHA-256 `1ed70af0494a92b69a40e12feffd7b47ad4c92b3d70ad0987fee77212b51635c`.
- `assets/earth-night.png`: NASA SVS 2916, “Earth At Night”, 2048×1024 image.
  <https://svs.gsfc.nasa.gov/2916/>
  SHA-256 `28407a1a802868852b3c232dbeaf16b5165e8200898cc7df6a2fec70708556cd`.
- `assets/earth-clouds.jpg`: NASA Visible Earth 57747, “Blue Marble: Clouds”,
  2048×1024 image.
  <https://visibleearth.nasa.gov/images/57747/blue-marble-clouds/77558l>
  SHA-256 `daddaad84d7a33bbbc86cdda3f591099f57cee8607b7bcf3b67eb7e4f7a1c793`.

NASA identification and insignia are not included and NASA endorsement is not
implied.

## Open-Meteo

Optional online city search uses the Open-Meteo Geocoding API. No Open-Meteo
data is redistributed. See <https://open-meteo.com/en/terms> and
<https://open-meteo.com/en/license>.

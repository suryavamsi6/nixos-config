{ pkgs, serpantinum, backend ? import ./backend.nix { inherit pkgs; } }:
serpantinum.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
    pkgs.python3
    pkgs.qt6.qtshadertools
  ];

  postInstall = (old.postInstall or "") + ''
    worldClockRoot=${./.}
    worldClockShare="$out/share/serpantinum"

    install -Dm755 ${backend}/bin/serpantinum-world-clock-backend \
      "$worldClockShare/bin/serpantinum-world-clock-backend"

    cp -r "$worldClockRoot/qml/." "$worldClockShare/quickshell/"
    mkdir -p "$worldClockShare/assets/worldclock"
    cp -r "$worldClockRoot/assets/." "$worldClockShare/assets/worldclock/"
    chmod -R u+w "$worldClockShare/assets/worldclock"
    cp "$worldClockRoot/LICENSES.md" "$worldClockShare/assets/worldclock/LICENSES.md"
    cp "$worldClockRoot/data/ODbL-1.0.txt" "$worldClockShare/assets/worldclock/ODbL-1.0.txt"

    # ShaderEffect requires a portable QSB; Qt Quick 3D CustomMaterial snippets
    # remain source and are conditioned by Qt Quick 3D's runtime shader generator.
    for shader in "$worldClockShare/assets/worldclock/shaders/"*.effect.frag; do
      qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o "$shader.qsb" "$shader" || exit 1
    done

    python "$worldClockRoot/scripts/patch_serpantinum.py" \
      --root "$worldClockShare" \
      --expected-version 2.1.0 \
      --expected-revision 44d33831ab6314e7d2d7f0323c1fc023cb08804c
  '';
})

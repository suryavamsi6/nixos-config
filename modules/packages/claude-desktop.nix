# Claude Desktop (claude.ai) from Anthropic's official Linux .deb.
# Chat, Cowork, and Claude Code. The launcher name is "Claude".
#
# The tree stays co-located under lib/claude-desktop so /proc/self/exe and
# process.resourcesPath stay inside this store path. No FHS env: Claude Code
# sessions inherit the wrapper, and bwrap would hide /etc/ssh, gitconfig,
# and sudo. Host helpers the bundle spawns by absolute path (/bin/bash,
# secret-tool, busctl, ps) are rewritten to store paths inside app.asar.
# chrome-sandbox stays mode 0755; NixOS user namespaces supply the sandbox.
#
# Cowork's VM is probed the same way as the host helpers: virtiofsd and
# OVMF firmware by fixed /usr paths (rewritten to store paths below),
# qemu-system-x86_64 through PATH (prepended by the wrapper).
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  addDriverRunpath,
  makeWrapper,
  asar,
  OVMF,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  bash,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libGL,
  libayatana-appindicator,
  libcap_ng,
  libdrm,
  libgbm,
  libnotify,
  libpulseaudio,
  libsecret,
  libseccomp,
  libuuid,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libxtst,
  nspr,
  nss,
  pango,
  pciutils,
  pipewire,
  procps,
  qemu_kvm,
  systemd,
  virtiofsd,
  wayland,
}:

let
  version = "3.1623.1";

  hostHelpers = {
    "/usr/bin/secret-tool" = "${libsecret}/bin/secret-tool";
    "/usr/bin/busctl" = "${systemd}/bin/busctl";
    "/bin/ps" = "${procps}/bin/ps";
    "/usr/bin/pgrep" = "${procps}/bin/pgrep";
    "/bin/bash" = "${bash}/bin/bash";
    # Cowork VM probes. nixpkgs' OVMF.fd ships OVMF_CODE.fd/OVMF_VARS.fd
    # (the app's fallback candidate), not the Debian-only 4M files, so the
    # first firmware candidate stays a dead path the app skips over.
    "/usr/libexec/virtiofsd" = "${virtiofsd}/bin/virtiofsd";
    "/usr/share/OVMF/OVMF_CODE_4M.fd" = "${OVMF.fd}/FV/OVMF_CODE_4M.fd";
    "/usr/share/OVMF/OVMF_CODE.fd" = "${OVMF.fd}/FV/OVMF_CODE.fd";
  };

  rewriteHelper = literal: target: ''
    files=$(grep -rlF --include='*.js' '"${literal}"' "$work/app" || true)
    if [[ -z $files ]]; then
      echo "claude-desktop: literal \"${literal}\" not found in app.asar" >&2
      exit 1
    fi
    for f in $files; do
      substituteInPlace "$f" --replace-fail '"${literal}"' '"${target}"'
      patched+=("$f")
    done
    if grep -rqE "[\"'\`]${literal}[\"'\`]" "$work/app"; then
      echo "claude-desktop: literal ${literal} still present in app.asar" >&2
      exit 1
    fi
  '';

  passwordStorePassthrough = ''
    if [[ -n ''${CLAUDE_PASSWORD_STORE-} ]]; then
      set -- "--password-store=$CLAUDE_PASSWORD_STORE" "$@"
    fi
  '';
in
stdenv.mkDerivation {
  pname = "claude-desktop";
  inherit version;

  src = fetchurl {
    url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${version}_amd64.deb";
    hash = "sha256-cxZ30vObKnND7jgexdM5bdKOwdgyz8sfnkoCLp6A6ts=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    asar
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libcap_ng
    libdrm
    libgbm
    libseccomp
    libxkbcommon
    nspr
    nss
    pango
    pipewire
    stdenv.cc.cc.lib
    systemd
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
  ];

  runtimeDependencies = map lib.getLib [
    libGL
    libayatana-appindicator
    libnotify
    libpulseaudio
    libsecret
    libuuid
    pciutils
    pipewire
    systemd
    wayland
    libxtst
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile "$src" \
      | tar -x --no-same-owner --no-same-permissions
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -a usr/lib usr/share $out/
    makeWrapper $out/lib/claude-desktop/claude-desktop \
      $out/bin/claude-desktop \
      --prefix VK_ADD_DRIVER_FILES : \
        "${addDriverRunpath.driverLink}/share/vulkan/icd.d" \
      --prefix PATH : "${lib.makeBinPath [ qemu_kvm ]}" \
      --run ${lib.escapeShellArg passwordStorePassthrough}
    substituteInPlace $out/share/applications/com.anthropic.Claude.desktop \
      --replace-fail 'Exec=claude-desktop' "Exec=$out/bin/claude-desktop"
    runHook postInstall
  '';

  postInstall = ''
    resources=$out/lib/claude-desktop/resources
    work=$(mktemp -d)
    patched=()

    asar extract "$resources/app.asar" "$work/app"

    ${lib.concatStrings (lib.mapAttrsToList rewriteHelper hostHelpers)}

    for f in "''${patched[@]}"; do
      rm -f "$work/app/compile-cache/$(basename "$f")".*.jsc
    done

    (cd "$resources/app.asar.unpacked" && find . -type f | sort) \
      > "$work/unpacked"
    unpack="{$(sed "s|^\./|$work/app/|" "$work/unpacked" | paste -sd,)}"
    mkdir "$work/out"
    asar pack "$work/app" "$work/out/app.asar" --unpack "$unpack"

    diff -r "$resources/app.asar.unpacked" "$work/out/app.asar.unpacked"
    asar list --is-pack "$work/out/app.asar" \
      | sed -n 's|^unpack *: /|./|p' | sort | diff "$work/unpacked" -
    while read -r f; do
      chmod --reference="$resources/app.asar.unpacked/$f" \
        "$work/out/app.asar.unpacked/$f"
    done < "$work/unpacked"

    rm -r "$resources/app.asar" "$resources/app.asar.unpacked"
    mv "$work/out/app.asar" "$work/out/app.asar.unpacked" "$resources/"
    rm -r "$work"
  '';

  preFixup = ''
    addAutoPatchelfSearchPath "$out/lib/claude-desktop"
  '';

  appendRunpaths = [
    "${lib.getLib libGL}/lib"
    "${addDriverRunpath.driverLink}/lib"
  ];

  meta = {
    description = "Claude Desktop for Linux";
    homepage = "https://claude.ai";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "claude-desktop";
  };
}

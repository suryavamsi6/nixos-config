# Zoom VDI Universal Plugin 6.6.11 — media offload for Zoom-inside-Citrix.
# Must match the Zoom VDI client version in the virtual desktop.
#
# libZoomPlugin.so is dlopened by Nix Citrix (patchelf'd).
# The zoom helper is exec'd as a child of wfica (pipes/PPid); do not put it
# in buildFHSEnv/bwrap. Patchelf its interpreter so it does not use NixOS's
# /lib64 stub ld. ZoomMedia.ini overwrites PATH and LD_LIBRARY_PATH, so tools
# and extra libs must live in those ini paths.
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  writeShellScript,
  coreutils,
  dbus,
  findutils,
  fontconfig,
  freetype,
  gawk,
  glib,
  gnugrep,
  gnused,
  inetutils,
  iproute2,
  iputils,
  iw,
  libGL,
  libkrb5,
  libpulseaudio,
  libx11,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxshmfence,
  libxtst,
  libxv,
  libxcb,
  libxcb-cursor,
  libxcb-image,
  libxcb-keysyms,
  libxcb-render-util,
  libxcb-util,
  libxcb-wm,
  pciutils,
  procps,
  pulseaudio,
  udev,
  which,
  wirelesstools,
  zlib,
}:

let
  version = "6.6.11.26890";

  pacmdForZoom = writeShellScript "pacmd" ''
    set -euo pipefail
    pactl=${lib.getBin pulseaudio}/bin/pactl
    awk=${lib.getExe gawk}
    case "''${1:-}" in
      --version|-v) echo "pacmd 17.0" ;;
      list-sinks|list-sources)
        kind=''${1#list-}
        "$pactl" list "$kind" | "$awk" '
          /^[[:space:]]*Name:/ {
            name=$2
            for (i=3;i<=NF;i++) name=name " " $i
            print "\tname: <" name ">"
          }
          /^[[:space:]]*Owner Module:/ { print "\tmodule: " $3 }
        '
        ;;
      unload-module) exec "$pactl" unload-module "''${2:-}" ;;
      *)
        echo "pacmd: unsupported command: $*" >&2
        exit 1
        ;;
    esac
  '';

  getbssidForZoom = writeShellScript "getbssid.sh" ''
    DEVICE_LIST=$(iw dev | awk '$1=="Interface"{print $2}')
    for d in $DEVICE_LIST ; do
      bssid=$(iw dev "$d" link | sed -n 's/.*Connected to \([0-9a-f:]\+\).*/\1/p')
      if [ -n "$bssid" ]; then
        echo "$bssid"
      fi
    done
  '';

  lsbReleaseForZoom = writeShellScript "lsb_release" ''
    case "''${1:-}" in
      -i) echo "Distributor ID: Ubuntu" ;;
      -d) echo "Description:    Ubuntu 22.04.5 LTS" ;;
      -r) echo "Release:        22.04" ;;
      -c) echo "Codename:       jammy" ;;
      *) cat <<'EOF'
Distributor ID: Ubuntu
Description:    Ubuntu 22.04.5 LTS
Release:        22.04
Codename:       jammy
EOF
      ;;
    esac
  '';

  extraLibs = [
    dbus
    fontconfig
    freetype
    glib
    libGL
    libkrb5
    libpulseaudio
    libx11
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxshmfence
    libxtst
    libxv
    libxcb
    libxcb-cursor
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libxcb-util
    libxcb-wm
    stdenv.cc.cc
    udev
    zlib
  ];

  extraLibPath = lib.makeLibraryPath extraLibs;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "zoomvdi-universal-plugin";
  inherit version;

  src = fetchurl {
    url = "https://zoom.us/download/vdi/${version}/zoomvdi-universal-plugin-ubuntu_6.6.11.deb";
    hash = "sha256-JffNfGU46FmDteDV00HRlGFHN06cEmos/bXJCFvSQM8=";
    curlOptsList = [
      "-A"
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
    ];
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = extraLibs;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontAutoPatchelf = true;
  dontWrapQtApps = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/etc/zoomvdi/citrix
    dpkg-deb -x $src $out
    mv $out/usr/lib $out/lib
    rm -rf $out/usr $out/etc/udev

    plugin=$out/lib/zoomvdi-universal-plugin
    cp ${getbssidForZoom} $plugin/getbssid.sh
    cp ${pacmdForZoom} $plugin/pacmd
    cp ${lsbReleaseForZoom} $plugin/lsb_release
    chmod +x $plugin/getbssid.sh $plugin/pacmd $plugin/lsb_release

    # Citrix execs $plugin/zoom with LD_LIBRARY_PATH=plugin:Qt/lib only
    # (it ignores extra ini dirs for this spawn). Put Nix libs next to the ELF.
    for dir in ${lib.escapeShellArgs (lib.splitString ":" extraLibPath)}; do
      [ -d "$dir" ] || continue
      for so in "$dir"/lib*.so*; do
        [ -e "$so" ] || continue
        base=$(basename "$so")
        if [ ! -e "$plugin/$base" ]; then
          ln -sfn "$so" "$plugin/$base"
        fi
      done
    done

    # Citrix execs this path (sibling of libZoomPlugin.so) and inherits
    # wfica's LD_LIBRARY_PATH, which does not include libz. Wrap in place.
    mv $plugin/zoom $plugin/.zoom-real
    makeWrapper $plugin/.zoom-real $plugin/zoom \
      --set LD_LIBRARY_PATH "$plugin:$plugin/Qt/lib:${extraLibPath}" \
      --prefix PATH : "$out/bin" \
      --set-default XDG_CURRENT_DESKTOP Hyprland \
      --set-default GDMSESSION hyprland \
      --set QT_QPA_PLATFORM xcb \
      --unset QT_QPA_PLATFORMTHEME \
      --unset PULSE_RUNTIME_PATH \
      --unset PULSE_STATE_PATH \
      --unset PULSE_CONFIG_PATH \
      --unset LD_PRELOAD
    ln -sfn $plugin/zoom $out/bin/zoom
    ln -sfn ${pacmdForZoom} $out/bin/pacmd
    ln -sfn ${lsbReleaseForZoom} $out/bin/lsb_release
    ln -sfn ${lib.getBin pulseaudio}/bin/pactl $out/bin/pactl
    ln -sfn ${lib.getExe gnugrep} $out/bin/grep
    ln -sfn ${lib.getExe gawk} $out/bin/awk
    ln -sfn ${lib.getExe gnused} $out/bin/sed
    ln -sfn ${coreutils}/bin/cut $out/bin/cut
    ln -sfn ${coreutils}/bin/cat $out/bin/cat
    ln -sfn ${coreutils}/bin/env $out/bin/env
    ln -sfn ${coreutils}/bin/head $out/bin/head
    ln -sfn ${coreutils}/bin/tr $out/bin/tr
    ln -sfn ${coreutils}/bin/ls $out/bin/ls
    ln -sfn ${coreutils}/bin/uname $out/bin/uname
    ln -sfn ${inetutils}/bin/hostname $out/bin/hostname
    ln -sfn ${iproute2}/bin/ip $out/bin/ip
    ln -sfn ${iw}/bin/iw $out/bin/iw
    ln -sfn ${wirelesstools}/bin/iwconfig $out/bin/iwconfig
    ln -sfn ${pciutils}/bin/lspci $out/bin/lspci
    ln -sfn ${iputils}/bin/ping $out/bin/ping
    ln -sfn ${procps}/bin/pkill $out/bin/pkill
    ln -sfn ${lib.getExe which} $out/bin/which
    ln -sfn ${findutils}/bin/xargs $out/bin/xargs

    {
      echo '[ENV]'
      echo "PATH=$out/bin/"
      echo 'BIN=zoom'
      echo "LD_LIBRARY_PATH=$plugin/:$plugin/Qt/lib/:${extraLibPath}"
      echo 'SSB_HOME=~/.zoomvdi'
      echo 'CONFIG_PATH=~/.zoomvdi'
      echo '[LOG]'
      echo 'MAX_FILE_COUNT=10'
      echo 'MAX_FILE_SIZE=30'
      echo '[FEATURE]'
      echo 'SHAREOFFLOAD=1'
      echo 'VIRTUALBACKGROUND=1'
      echo '[DEVICE_LOCATION]'
      echo 'ISINOFFICE=0'
      echo '[OS]'
      echo 'OS_DISTRO=ubuntu'
    } > $out/etc/zoomvdi/ZoomMedia.ini
    cp $out/etc/zoomvdi/ZoomMedia.ini $out/etc/zoomvdi/citrix/ZoomMedia.ini
    runHook postInstall
  '';

  preFixup = ''
    plugin=$out/lib/zoomvdi-universal-plugin
    addAutoPatchelfSearchPath $plugin
    addAutoPatchelfSearchPath $plugin/Qt/lib
  '';

  postFixup = ''
    plugin=$out/lib/zoomvdi-universal-plugin
    autoPatchelf $plugin/libZoomPlugin.so
    autoPatchelf $plugin/.zoom-real $plugin/aomhost $plugin/crash_processor
    for so in $plugin/*.so $plugin/*.so.*; do
      [ -e "$so" ] || continue
      [ -L "$so" ] && continue
      case "$so" in
        *libZoomPlugin.so) continue ;;
      esac
      autoPatchelf "$so" || true
    done
  '';

  passthru.pluginLib = "${finalAttrs.finalPackage}/lib/zoomvdi-universal-plugin/libZoomPlugin.so";

  meta = {
    description = "Zoom VDI Universal Plugin (Citrix media offload)";
    homepage = "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0060160";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})

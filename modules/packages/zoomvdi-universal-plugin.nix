# Zoom VDI Universal Plugin — media offload for Zoom-inside-Citrix.
# Must match the Zoom VDI client version in the virtual desktop (currently
# 7.0.11); a mismatched plugin loads fine but never connects.
#
# libZoomPlugin.so is dlopened by Nix Citrix (patchelf'd).
# The zoom helper is exec'd as a child of wfica (pipes/PPid); do not put it
# in buildFHSEnv/bwrap. Patchelf its interpreter so it does not use NixOS's
# /lib64 stub ld. ZoomMedia.ini overwrites PATH and LD_LIBRARY_PATH, so tools
# and extra libs must live in those ini paths.
#
# $plugin/zoom must stay the unwrapped ELF. The plugin authenticates whoever
# connects back to its socket against the helper it spawned, and part of that
# identity is /proc/<pid>/exe. Any exec wrapper leaves exe pointing at the
# wrapper's target, the plugin hangs up mid-handshake, and the helper exits 0
# after ~1s — which looks exactly like "Zoom crashed / VDI not connecting".
# So the wrapper's two jobs are done without exec: libraries via DT_RPATH,
# and environment/signal fixups via a DT_NEEDED constructor.
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  writeShellScript,
  alsa-lib,
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
  libdrm,
  libkrb5,
  libpulseaudio,
  libx11,
  libxcomposite,
  libxcursor,
  libxext,
  libxfixes,
  libxinerama,
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
  zstd,
}:

let
  # Zoom requires plugin/client version parity: a 6.6.x plugin silently refuses
  # to connect to a 7.0.x VDI client (helper spawns, handshake fails, exits).
  version = "7.0.11.27050";
  shortVersion = lib.versions.pad 3 version;

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
    alsa-lib
    dbus
    fontconfig
    freetype
    glib
    libGL
    libdrm
    libkrb5
    libpulseaudio
    libx11
    libxcomposite
    libxcursor
    libxext
    libxfixes
    libxi
    libxinerama
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
    zstd
  ];

  extraLibPath = lib.makeLibraryPath extraLibs;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "zoomvdi-universal-plugin";
  inherit version;

  src = fetchurl {
    url = "https://zoom.us/download/vdi/${version}/zoomvdi-universal-plugin-ubuntu_${shortVersion}.deb";
    hash = "sha256-1ADcgA74AhQaS6OGYEd2lu3bIwSvfW5oHG7p8XSErCo=";
    curlOptsList = [
      "-A"
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
    ];
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
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

    # wfica spawns the helper with SIGCHLD set to SIG_IGN, and an ignored
    # disposition survives execve. GLib's g_spawn_sync then loses the race to
    # the kernel auto-reaper and waitpid() returns ECHILD while probing
    # `pactl --version`, so Zoom logs "no pactl and pacmd found" and the
    # AV/VPT processes bail. Nothing outside the process can undo an inherited
    # SIG_IGN, and a wrapper that execs would break the exe identity check, so
    # this is linked into the helper itself as a DT_NEEDED constructor.
    # Only SIGCHLD is touched: resetting e.g. SIGPIPE to SIG_DFL would turn a
    # closed socket into a fatal signal. The mask is cleared because a process
    # that was not forked from wfica would start with an empty one.
    cat > zoomfix.c <<'EOF'
    #include <signal.h>
    #include <stdlib.h>
    #include <string.h>

    #ifndef ZOOM_BIN_PATH
    #define ZOOM_BIN_PATH "/usr/bin"
    #endif

    __attribute__((constructor)) static void zoomvdi_fix(void) {
      struct sigaction sa;
      memset(&sa, 0, sizeof sa);
      sa.sa_handler = SIG_DFL;
      sigaction(SIGCHLD, &sa, (void *)0);

      sigset_t set;
      sigemptyset(&set);
      sigprocmask(SIG_SETMASK, &set, (void *)0);

      /* The bundle ships libqxcb.so but no usable wayland platform plugin, so
         xcb is forced rather than defaulted: inheriting WAYLAND_DISPLAY from
         the session is enough to make Qt abort with "Could not find the Qt
         platform plugin". Citrix is X11-only anyway. */
      setenv("QT_QPA_PLATFORM", "xcb", 1);

      /* wfica exports XDG_CURRENT_DESKTOP but not GDMSESSION; Zoom reads both
         when picking a screen-capture backend. */
      setenv("GDMSESSION", "hyprland", 0);

      /* wfica's PATH does not include pactl/pacmd/lspci. Zoom then logs
         "no pactl and pacmd found" and talks audio through Citrix's Pulse
         client, which SIGSEGVs in threaded-ml when the mic opens. */
      setenv("PATH", ZOOM_BIN_PATH, 1);
    }
    EOF
    $CC -O2 -fPIC -shared -o $plugin/libzoomvdifix.so zoomfix.c \
      -DZOOM_BIN_PATH='"'"$out/bin"'"'

    ln -sfn $plugin/zoom $out/bin/zoom
    ln -sfn ${pacmdForZoom} $out/bin/pacmd
    ln -sfn ${pacmdForZoom} $plugin/pacmd
    ln -sfn ${lsbReleaseForZoom} $out/bin/lsb_release
    ln -sfn ${lib.getBin pulseaudio}/bin/pactl $out/bin/pactl
    ln -sfn ${lib.getBin pulseaudio}/bin/pactl $plugin/pactl
    ln -sfn ${pciutils}/bin/lspci $plugin/lspci
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
    autoPatchelf $plugin/zoom $plugin/aomhost $plugin/crash_processor
    autoPatchelf $plugin/Zoom_VDI_Plugin_Management || true

    # DT_RPATH rather than DT_RUNPATH: the 40 bundled Qt libraries carry no
    # runpath of their own, and only RPATH is inherited by transitive
    # dependencies. This is what the wrapper's LD_LIBRARY_PATH used to do —
    # wfica's LD_LIBRARY_PATH, which the helper inherits, has no libz/libzstd.
    # aomhost and crash_processor need it too; they used to inherit the
    # wrapper's environment from zoom.
    rpath="$plugin:$plugin/Qt/lib:${extraLibPath}"
    for exe in zoom aomhost crash_processor; do
      patchelf --force-rpath --set-rpath "$rpath" $plugin/$exe
    done
    patchelf --add-needed libzoomvdifix.so $plugin/zoom
    # Every bundled object needs its own runpath. Inheriting the executable's
    # DT_RPATH is not enough: the loader prunes that list as it goes, so late
    # lookups (libxkbcommon, libz, libzstd, libEGL...) were searching only a
    # subset of it and falling through to the system paths, where they do not
    # exist. The vendor Qt tree ships with no runpath at all, so patch it too.
    for so in $plugin/*.so $plugin/*.so.* $plugin/Qt/lib/*.so*; do
      [ -e "$so" ] || continue
      [ -L "$so" ] && continue
      case "$so" in
        *libZoomPlugin.so) continue ;;
      esac
      autoPatchelf "$so" || true
    done
    for d in $plugin/Qt/plugins $plugin/Qt/qml; do
      [ -d "$d" ] || continue
      autoPatchelf "$d" || true
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

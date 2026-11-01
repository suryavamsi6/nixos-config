# SMART disk health — smartd autodetect plus a JSON snapshot Gatus can read.
#
# Every host with a disk gets this: the desktop (two NVMe SSDs), the homelab
# (one NVMe) and the pi (an SD card and a spinning Seagate over USB).
#
# Two separate jobs, deliberately not merged:
#   * smartd is the *event* path. It polls, writes failures to the journal and
#     runs a hook that appends to /var/lib/disk-health/alerts, so a failure
#     survives the journal being rotated away.
#   * disk-health is the *state* path. A timer rewrites
#     /var/lib/disk-health/health.json every 15 minutes; the homelab's
#     homelab-stats feed serves that file at /disk.json, which is what Gatus
#     checks and Homepage renders.
#
# Why a file rather than a listener: the alternative was a small HTTP daemon on
# three hosts to publish one JSON document. The homelab already runs such a feed
# for its dashboard, so the file is the only new interface.
#
# Deliberate choices:
#   * `autodetect` (DEVICESCAN) instead of a hardcoded device list. The pi's
#     spinner is /dev/sda today, but USB enumeration has already moved it once
#     (see the usb-storage quirks workaround in nixos-raspberry-pi.nix).
#   * `-n standby` so polling never spins up a sleeping disk. This matters for
#     the pi: without it the platter never stops.
#   * `smartctl -j` rather than parsing the human-readable report. The text
#     layout differs between ATA, NVMe and USB-bridged drives, and the JSON
#     schema does not.
#   * A disk that cannot answer SMART (SD card, USB bridge without passthrough)
#     is reported as `"smart": false`, never as a failure.
{ lib, ... }:
{
  options.flake.modules.nixos.diskHealth = lib.mkOption {
    type = lib.types.deferredModule;
    default =
      { pkgs, ... }:
      let
        diskHealth = pkgs.writeShellApplication {
          name = "disk-health";
          runtimeInputs = [
            pkgs.smartmontools
            pkgs.util-linux
            pkgs.coreutils
            pkgs.gawk
            pkgs.jq
          ];
          text = ''
            set -uo pipefail

            state_dir="''${DISK_HEALTH_STATE_DIR:-/var/lib/disk-health}"
            alert_file=$state_dir/alerts
            install -d -m 0755 "$state_dir"

            # zram is a swap device that lsblk reports as type "disk"; it has
            # no SMART data and would only add noise to the report.
            devs=$(lsblk -dn -o NAME,TYPE | awk '$2=="disk" && $1 !~ /^zram/ {print "/dev/"$1}')

            records=()
            for dev in $devs; do
              # `-n standby` exits 2 when the disk is asleep: skip it instead of
              # waking it. `-j` emits JSON even on that exit, hence no `set -e`.
              status=0
              json=$(smartctl -j -H -i -A -n standby "$dev" 2>/dev/null) || status=$?

              if [ "$status" -eq 2 ]; then
                records+=("$(jq -nc --arg dev "$dev" '{device: $dev, model: null, smart: false,
                  health: "STANDBY", temperature: null, reallocated: null, pending: null,
                  error: null}')")
                continue
              fi

              # USB bridges usually need an explicit device type; vendor SATA
              # and NVMe drives do not. Retry once with `-d sat` if the first
              # attempt produced no usable smartctl object.
              if ! jq -e '.smartctl.exit_status? != null' <<<"$json" >/dev/null 2>&1; then
                status=0
                alt=$(smartctl -j -d sat -H -i -A -n standby "$dev" 2>/dev/null) || status=$?
                [ "$status" -eq 2 ] && alt=$(jq -nc '{smartctl: {exit_status: 0}}')
                [ -n "$alt" ] && json=$alt
              fi

              # ATTR 5 = reallocated sector count, 197 = current pending sectors;
              # both precede an outright failure. NVMe keeps its equivalents in
              # `nvme_smart_health_information_log` instead, but a non-zero media
              # error count there already shows up in smart_status.
              # exit_status bits (smartctl(8)): 1 = CLI error, 2 = device open
              # failed, 4 = a SMART command failed, 8 = disk is failing now.
              # Anything below 4 means the drive answered, so SMART is available
              # even if an individual attribute could not be read.
              records+=("$(jq -nc \
                --arg dev "$dev" \
                --argjson j "$json" \
                '{
                  device: $dev,
                  model: ($j.model_name // $j.device.model // null),
                  smart: ((($j.smartctl.exit_status // 0) | . < 4)),
                  health: (
                    if ($j.smart_status.passed // null) == true then "PASSED"
                    elif ($j.smart_status.passed // null) == false then "FAILED"
                    else "UNKNOWN" end),
                  temperature: ($j.temperature.current // null),
                  reallocated: ([($j.ata_smart_attributes.table // [])[] | select(.id == 5) | .raw.value] | first // null),
                  pending: ([($j.ata_smart_attributes.table // [])[] | select(.id == 197) | .raw.value] | first // null),
                  # Non-empty only when smartmontools complained, e.g. "Read NVMe
                  # SMART/Health Information failed: Permission denied" when run
                  # without CAP_SYS_ADMIN. Keeps an unreadable disk from looking
                  # like a healthy one in the dashboard.
                  error: ([($j.smartctl.messages // [])[] | select(.severity == "error") | .string] | first // null)
                }')")
            done

            disks=$(printf '%s\n' "''${records[@]:-}" | jq -s -c 'map(select(. != null))')

            # Failing = SMART said FAILED, or either pre-failure counter moved
            # off zero. STANDBY/UNKNOWN are not failures: an SD card cannot
            # answer SMART at all and that is expected.
            failing=$(jq -c '
              [ .[] | select(.health == "FAILED") | .device ]
              + [ .[] | select((.reallocated // 0) > 0) | .device ]
              + [ .[] | select((.pending // 0) > 0) | .device ]
              | unique' <<<"$disks")

            alerts='[]'
            if [ -r "$alert_file" ]; then
              alerts=$(jq -R -s -c 'split("\n") | map(select(length > 0)) | .[-5:]' "$alert_file")
            fi

            ok=true
            [ "$(jq 'length' <<<"$failing")" -eq 0 ] || ok=false
            [ "$(jq 'length' <<<"$alerts")" -eq 0 ] || ok=false

            jq -n -c \
              --argjson ok "$ok" \
              --argjson disks "$disks" \
              --argjson failing "$failing" \
              --argjson alerts "$alerts" \
              --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
              '{ok: $ok, generated: $generated, disks: $disks, failing: $failing, alerts: $alerts}' \
              > "$state_dir/health.json.tmp"
            mv "$state_dir/health.json.tmp" "$state_dir/health.json"
            chmod 0644 "$state_dir/health.json"
          '';
        };

        # smartd's -M exec hook. There is no MTA on any of these hosts, so
        # smartd's own mail path would fail silently; this records the event
        # where the JSON feed can see it and leaves the journal line alone.
        # writeShellApplication rather than writeShellScript: smartd's default
        # warning script clobbers PATH to just sed + hostname before exec'ing
        # this hook, so coreutils must come from runtimeInputs.
        smartdHook = pkgs.writeShellApplication {
          name = "smartd-hook";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            state_dir="''${DISK_HEALTH_STATE_DIR:-/var/lib/disk-health}"
            install -d -m 0755 "$state_dir"
            printf '%s %s %s\n' \
              "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
              "''${SMARTD_DEVICE:-unknown}" \
              "''${SMARTD_FAILTYPE:-unknown}: ''${SMARTD_MESSAGE:-unknown}" \
              >> "$state_dir/alerts"
            tail -n 50 "$state_dir/alerts" > "$state_dir/alerts.tmp"
            mv "$state_dir/alerts.tmp" "$state_dir/alerts"
          '';
        };
      in
      {
        services.smartd = {
          enable = true;
          autodetect = true;
          # -n standby: never wake a sleeping disk just to poll it.
          # -a: health, attributes, error log and self-test log.
          # -M exec: run the hook instead of smartd's mail path on any
          # warning. This is a smartd.conf *directive*, not a command-line
          # option: smartmontools 7.5 dropped the command-line `-M`, and the
          # NixOS module routes notifications through the config file for the
          # same reason. The parser rejects `-M` without `-m`, so the address
          # is a placeholder; smartd's default warning script still execs the
          # hook with the SMARTD_* environment untouched.
          defaults.monitored = "-a -n standby -m <nomailer> -M exec ${smartdHook}";
          # defaults.autodetected inherits monitored, so DEVICESCAN gets the
          # hook too.
          # Every notifier here needs either an MTA or a graphical session; the
          # hook below is the notification path instead.
          notifications = {
            mail.enable = false;
            wall.enable = false;
            x11.enable = false;
            systembus-notify.enable = false;
          };
        };

        systemd.tmpfiles.rules = [
          "d /var/lib/disk-health 0755 root root -"
        ];

        systemd.services.disk-health = {
          description = "Snapshot SMART disk health to JSON";
          # smartd must exist first so the first snapshot already reflects a
          # live daemon; they write separate files, so no ordering beyond that.
          after = [ "smartd.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${diskHealth}/bin/disk-health";
          };
        };

        systemd.timers.disk-health = {
          description = "Refresh the SMART disk health snapshot";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5min";
            OnUnitActiveSec = "15min";
            Persistent = false;
          };
        };

        environment.systemPackages = [ pkgs.smartmontools ];
      };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.firn-link;
  # The passphrase is added when iwd starts, so it stays out of the store.
  networkSettings = pkgs.writeText "firn-link-settings" (
    lib.generators.toINI { } {
      Settings.AutoConnect = false;
      IPv4 = {
        Address = "10.88.0.2";
        Netmask = "255.255.255.0";
      };
    }
  );
  firn-link = pkgs.writeShellApplication {
    name = "firn-link";
    runtimeInputs = [
      pkgs.iwd
      pkgs.iproute2
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = ''
      previous="''${XDG_RUNTIME_DIR:-/tmp}/firn-link.previous"

      connected() {
        iwctl station wlan0 show | sed -e 's/\x1b\[[0-9;]*m//g' \
          -ne 's/^ *Connected network *\(.*[^ ]\) *$/\1/p'
      }

      case "''${1:-on}" in
        on)
          echo "Joining firn-link..."
          # iwd does not return to a network it was moved off.
          current=$(connected)
          if [ -n "$current" ] && [ "$current" != firn-link ]; then
            printf '%s\n' "$current" > "$previous"
          fi
          # iwd connects only to networks in its scan results.
          iwctl station wlan0 scan 2>/dev/null || true
          for _ in $(seq 30); do
            iwctl station wlan0 get-networks | grep -q firn-link && break
            sleep 0.5
          done
          iwctl station wlan0 connect firn-link
          for _ in $(seq 20); do
            if ip -4 addr show wlan0 | grep -q 'inet 10\.88\.0\.2/'; then
              echo "Connected as 10.88.0.2: ssh m4@10.88.0.2"
              exit 0
            fi
            sleep 0.5
          done
          echo "Joined firn-link, but 10.88.0.2 was not assigned" >&2
          exit 1
          ;;
        off)
          if [ -s "$previous" ]; then
            network=$(cat "$previous")
            iwctl station wlan0 connect "$network"
            rm -f "$previous"
            echo "Left firn-link for $network."
          else
            iwctl station wlan0 disconnect
            echo "Left firn-link; connect with: iwctl station wlan0 connect NETWORK"
          fi
          ;;
        *)
          echo "usage: firn-link [on|off]" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  options.services.firn-link = {
    enable = lib.mkEnableOption ''
      the firn-link command, which joins a build machine's firn-link Wi-Fi
      network as 10.88.0.2 for SSH where no shared network allows it. Wi-Fi
      is then addressed by iwd instead of dhcpcd
    '';

    passphraseFile = lib.mkOption {
      type = lib.types.str;
      example = "/var/lib/firn-link/passphrase";
      description = ''
        File holding the firn-link network's passphrase, read when iwd
        starts. A path string, so the passphrase stays out of the store.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ firn-link ];

    # dhcpcd misses switches between networks, which brcmfmac makes without
    # dropping the link, so iwd addresses Wi-Fi and gives firn-link its address.
    networking.wireless.iwd.settings = {
      General.EnableNetworkConfiguration = true;
      Network.NameResolvingService = if config.services.resolved.enable then "systemd" else "resolvconf";
    };
    # Without the passphrase, iwd still starts for every other network.
    systemd.services.iwd.preStart = ''
      umask 077
      mkdir -p /var/lib/iwd
      if passphrase=$(cat ${lib.escapeShellArg cfg.passphraseFile}); then
        {
          printf '[Security]\nPassphrase=%s\n\n' "$passphrase"
          cat ${networkSettings}
        } > /var/lib/iwd/firn-link.psk
      else
        echo "firn-link: cannot read ${cfg.passphraseFile}; leaving it out" >&2
        rm -f /var/lib/iwd/firn-link.psk
      fi
    '';
    networking.dhcpcd = {
      denyInterfaces = [ "wlan0" ];
      wait = "background";
    };
    # resolvconf restarts nscd on each DNS update, several per connection.
    systemd.services.nscd.startLimitIntervalSec = 0;
  };
}

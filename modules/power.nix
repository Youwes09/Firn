# Sleep does not work yet, so a closed lid powers off.
{ config, lib, ... }:
let
  cpufreq = "/sys/devices/system/cpu/cpufreq";
in
{
  config = lib.mkIf config.hardware.firn.enable {
    # Nothing throttles the M4's CPUs yet: at full clock the die passes 100 C
    # within seconds. These caps hold it near 74 C under load.
    boot.kernelModules = [ "apple_soc_cpufreq" ];
    # Lets the Wi-Fi and Bluetooth link enter L1.2 when idle.
    boot.kernelParams = [ "pcie_aspm.policy=powersupersave" ];
    systemd.services.firn-cpu-cap = {
      description = "Cap the CPU clocks";
      wantedBy = [ "sysinit.target" ];
      after = [ "systemd-modules-load.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        for _ in $(seq 50); do
          [ -e ${cpufreq}/policy0 ] && [ -e ${cpufreq}/policy1 ] && break
          sleep 0.1
        done
        for policy in ${cpufreq}/policy*; do
          # The P cluster reaches 4.1 GHz, the E cluster 2.8 GHz.
          if [ "$(cat "$policy/cpuinfo_max_freq")" -gt 3000000 ]; then
            echo 1800000 > "$policy/scaling_max_freq"
          else
            echo 2172000 > "$policy/scaling_max_freq"
          fi
        done
      '';
    };

    systemd.sleep.settings.Sleep = {
      AllowSuspend = "no";
      AllowHibernation = "no";
      AllowHybridSleep = "no";
      AllowSuspendThenHibernate = "no";
    };
    services.logind.settings.Login = {
      HandleLidSwitch = "poweroff";
      HandleLidSwitchExternalPower = "poweroff";
      HandleLidSwitchDocked = "ignore";
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
    };
  };
}

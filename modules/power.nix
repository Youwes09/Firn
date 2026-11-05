# Sleep does not work yet, so a closed lid powers off.
{ config, lib, ... }:
let
  cpufreq = "/sys/devices/system/cpu/cpufreq";
in
{
  config = lib.mkIf config.hardware.firn.enable {
    boot.kernelModules = [ "apple_soc_cpufreq" ];
    # Lets the Wi-Fi and Bluetooth link enter L1.2 when idle.
    boot.kernelParams = [ "pcie_aspm.policy=powersupersave" ];

    # The CPU thermal zone holds the hot spot at 90 C under sustained load,
    # but its sensor updates once a second and the hot spot follows a load
    # within 0.1 s: four P cores starting at 3.9 GHz add 48 C. Above
    # 2.868 GHz a step from a warm package passes 100 C before the zone can
    # act, so the P cluster stays at or below it. The E cluster needs no cap.
    systemd.services.firn-cpu-cap = {
      description = "Cap the P cluster's clock";
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
            echo 2868000 > "$policy/scaling_max_freq"
          fi
        done
      '';
    };

    # power_allocator's gains for the CPU thermal zone, in its fixed point
    # (x 1024): 0.08 W per C either side of the 90 C target, and an
    # integral of 0.008 that only runs within 5 C of it, so it cannot wind
    # up while the CPUs idle cool. Higher gains swing the hot spot between
    # 65 and 101 C, as it reacts faster than the sensor reports.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="thermal", KERNEL=="thermal_zone*", ATTR{type}=="cpu-thermal", ATTR{k_po}="82", ATTR{k_pu}="82", ATTR{k_i}="8", ATTR{integral_cutoff}="5000"
    '';

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

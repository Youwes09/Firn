# Sleep does not work yet, so a closed lid powers off.
{ config, lib, ... }:
{
  config = lib.mkIf config.hardware.firn.enable {
    boot.kernelModules = [ "apple_soc_cpufreq" ];
    # Lets the Wi-Fi and Bluetooth link enter L1.2 when idle.
    boot.kernelParams = [ "pcie_aspm.policy=powersupersave" ];

    # The gains power_allocator estimates for the hot spot limit-cycle
    # between 95 and 115 C. These hold it at 105 C with a single overshoot.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="thermal", KERNEL=="thermal_zone*", ATTR{type}=="cpu-thermal", ATTR{k_po}="205", ATTR{k_pu}="100", ATTR{k_i}="52"
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

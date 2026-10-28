# Suspend and hibernate do not work on the J713 yet. A closed lid powers off
# rather than leaving the Air running in a bag.
{ config, lib, ... }:
{
  config = lib.mkIf config.hardware.firn.enable {
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

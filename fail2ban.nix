
########################################################################
#                                                                      #
# DO NOT EDIT THIS FILE, ALL EDITS SHOULD BE DONE IN THE GIT REPO,     #
# PUSHED TO GITHUB AND PULLED HERE.                                    #
#                                                                      #
# LOCAL EDITS WILL BE OVERWRITTEN.                                     #
#                                                                      #
########################################################################

{ config, lib, ... }:

let
  cfg = config.settings.fail2ban;
in

with lib;

{
  options = {
    settings.fail2ban = {
      enable = mkOption {
        default = true;
        type = types.bool;
        description = ''
          Whether to start the fail2ban service.
        '';
      };
    };
  };

  config.services.fail2ban = {
    enable = cfg.enable;
    jails.ssh-iptables = lib.mkForce "";
    jails.ssh-iptables-extra = ''
      action   = iptables-multiport[name=SSH, port="${lib.concatMapStringsSep "," (p: toString p) config.services.openssh.ports}", protocol=tcp]
      maxretry = 3
      findtime = 3600
      bantime  = 3600
      filter   = sshd[mode=extra]
    '';
  };

}

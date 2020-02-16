
########################################################################
#                                                                      #
# DO NOT EDIT THIS FILE, ALL EDITS SHOULD BE DONE IN THE GIT REPO,     #
# PUSHED TO GITHUB AND PULLED HERE.                                    #
#                                                                      #
# LOCAL EDITS WILL BE OVERWRITTEN.                                     #
#                                                                      #
########################################################################

{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    settings.system.nix_channel = mkOption {
      type = types.str;
    };
  };

  config = {
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 40;
    };

    security = {
      sudo = {
        enable = true;
        wheelNeedsPassword = false;
      };
      pam.services.su.forwardXAuth = mkForce false;
    };

    environment = {
      # See https://nixos.org/nix/manual/#ssec-values for documentation on escaping ${
      shellInit = ''
        if [ "''${TERM}" != "screen" ] || [ -z "''${TMUX}" ]; then
          alias nixos-rebuild='printf "Please run nixos-rebuild only from within a tmux session." 2> /dev/null'
        fi
      '';
      shellAliases = {
        nix-env = ''printf "The nix-env command has been disabled. Please use nix-run or nix-shell instead." 2> /dev/null'';
        vi = "vim";
        # Have bash resolve aliases with sudo (https://askubuntu.com/questions/22037/aliases-not-available-when-using-sudo)
        sudo = "sudo ";
        whereami = "curl ipinfo.io";
      };
    };

    system.activationScripts = {
      settings_link = let
        hostname = config.networking.hostName;
        settings_path = "/etc/nixos/settings.nix";
      in ''
        if [ $(realpath ${settings_path}) != "/etc/nixos/hosts/${hostname}.nix" ]; then
          ln --force --symbolic hosts/${hostname}.nix ${settings_path}
        fi
      '';
      nix_channel_msf = {
        text = ''
          # We override the root nix channel with the one defined by settings.system.nix_channel
          echo "https://nixos.org/channels/nixos-${config.settings.system.nix_channel} nixos" > "/root/.nix-channels"
        '';
        # We overwrite the value set by the default NixOS activation snippet, that snippet should have run first
        # so that the additional initialisation has been performed.
        # See /run/current-system/activate for the currently defined snippets.
        deps = [ "nix" ];
      };
    };

    systemd.user.services.cleanup_nixenv = {
      enable = true;
      description = "Clean up nix-env";
      unitConfig.ConditionUser = "!@system";
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.nix}/bin/nix-env -e '.*'
      '';
      wantedBy = [ "default.target" ];
    };

    # No fonts needed on a headless system
    fonts.fontconfig.enable = mkForce false;

    # Given that our systems are headless, emergency mode is useless.
    # We prefer the system to attempt to continue booting so 
    # that we can hopefully still access it remotely.
    systemd.enableEmergencyMode = false;

    programs = {
      bash.enableCompletion = true;

      ssh = {
        startAgent = false;
        # We do not have GUIs
        setXAuthLocation = false;
      };

      tmux = {
        enable = true;
        newSession = true;
        clock24 = true;
        historyLimit = 10000;
        extraTmuxConf = ''
          set -g mouse on
        '';
      };
    };

    services = {
      fstrim.enable = true;
      # Avoid pulling in unneeded dependencies
      udisks2.enable = false;

      timesyncd = {
        enable = true;
        servers = mkDefault [
          "0.nixos.pool.ntp.org"
          "1.nixos.pool.ntp.org"
          "2.nixos.pool.ntp.org"
          "3.nixos.pool.ntp.org"
          "time.windows.com"
          "time.google.com"
        ];
      };

      htpdate = {
        enable = true;
        servers = [ "www.kernel.org" "www.google.com" "www.cloudflare.com" ];
      };

      journald = {
        rateLimitBurst = 1000;
        rateLimitInterval = "5s";
        extraConfig = ''
          Storage=persistent
        '';
      };

      # See man logind.conf
      logind = {
        extraConfig = ''
          HandlePowerKey=poweroff
          PowerKeyIgnoreInhibited=yes
        '';
      };

      avahi = {
        enable  = true;
        nssmdns = true;
        extraServiceFiles = {
          ssh = "${pkgs.avahi}/etc/avahi/services/ssh.service";
        };
        publish = {
          enable = true;
          domain = true;
          addresses   = true;
          workstation = true;
        };
      };
    };

    hardware = {
      enableRedistributableFirmware = true;
      cpu.intel.updateMicrocode = true;
      cpu.amd.updateMicrocode   = true;
    };

    documentation = {
      man.enable  = true;
      doc.enable  = false;
      dev.enable  = false;
      info.enable = false;
    };
  };
}

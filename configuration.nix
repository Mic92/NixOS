
########################################################################
#                                                                      #
# DO NOT EDIT THIS FILE, ALL EDITS SHOULD BE DONE IN THE GIT REPO,     #
# PUSHED TO GITHUB AND PULLED HERE.                                    #
#                                                                      #
# LOCAL EDITS WILL BE OVERWRITTEN.                                     #
#                                                                      #
########################################################################

# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, lib, pkgs, ... }:

{
  imports = (import ./settings.nix).imports;

  networking.hostName = (import ./settings.nix).hostname;

  # Select internationalisation properties.
  # i18n = {
  #   consoleFont = "Lat2-Terminus16";
  #   consoleKeyMap = "us";
  #   defaultLocale = "en_US.UTF-8";
  # };

  time.timeZone = (import ./settings.nix).timezone;

  environment = {
    systemPackages = with pkgs; [
      cryptsetup
      keyutils
      wget
      curl
      (import ./vim-config.nix)
      coreutils
      file
      htop
      iotop
      lsof
      psmisc
      rsync
      git
      acl
      mkpasswd
      unzip
      lm_sensors
      nmap
      traceroute
      bind
      python3
      nix-info
      nox
    ];
    # See https://nixos.org/nix/manual/#ssec-values for documentation on escaping ${
    shellInit = ''
      if [ "''${TERM}" != "screen" ] || [ -z "''${TMUX}" ]; then
        alias nixos-rebuild='printf "Please run nixos-rebuild only from within a tmux session.\c" 2> /dev/null'
      fi
    '';
    shellAliases = {
      # Have bash resolve aliases with sudo (https://askubuntu.com/questions/22037/aliases-not-available-when-using-sudo)
      sudo = "sudo ";
    };
    etc = {
      lustrate = {
        # Can we have this permanently enabled? --> Seems not. Keeping it here for reference.
        # What about /var/lib/docker ?? Other locations that we need to maintain on a working system?
        enable = false;
        target = "NIXOS_LUSTRATE";
        text = ''
          etc/nixos
          opt
          home
        '';
      };
    };
  };

  boot = {
    #kernelPackages = pkgs.linuxPackages_latest;

    kernelParams = [
      # Overwrite free'd memory
      #"page_poison=1"

      # Disable legacy virtual syscalls
      #"vsyscall=none"

      # Disable hibernation (allows replacing the running kernel)
      "nohibernate"
    ];

    kernel.sysctl = {
      # Prevent replacing the running kernel image w/o reboot
      "kernel.kexec_load_disabled" = true;

      # Disable bpf() JIT (to eliminate spray attacks)
      #"net.core.bpf_jit_enable" = mkDefault false;

      # ... or at least apply some hardening to it
      "net.core.bpf_jit_harden" = true;

      # Raise ASLR entropy
      "vm.mmap_rnd_bits" = 32;
    };

    tmpOnTmpfs = true;
  };

  fileSystems."/".options = [ "defaults" "acl" "noatime" ];

  zramSwap = {
    enable = true;
    memoryPercent = 40;
  };

  ## WARNING: Don't try to hibernate when you have at least one swap partition with this option enabled!
  ## We have no way to set the partition into which hibernation image is saved, so if your image ends up on an encrypted one you would lose it!
  ## WARNING #2: Do not use /dev/disk/by-uuid/… or /dev/disk/by-label/… as your swap device when using randomEncryption
  ## as the UUIDs and labels will get erased on every boot when the partition is encrypted. Best to use /dev/disk/by-partuuid/…
  #swapDevices.*.randomEncryption = {
  #  enable = true;
  #  cipher = <run cryptsetup benchmark>
  #};

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  programs = {
    bash.enableCompletion = true;
    
    ssh.startAgent = false;
    
    tmux = {
      enable = true;
      newSession = true;
      clock24 = true;
      historyLimit = 10000;
    };
  };

  services = {
    openssh = {
      enable = true;
      permitRootLogin = "no";
      forwardX11 = false;
      passwordAuthentication = false;
      challengeResponseAuthentication = false;
      extraConfig = ''
        StrictModes yes
        AllowAgentForwarding no
        TCPKeepAlive yes
        ClientAliveInterval 120
        ClientAliveCountMax 3
        UseDNS no
        GSSAPIAuthentication no
        KerberosAuthentication no
      '';
    };
    
    fstrim.enable = true;

    timesyncd = {
      enable = true;
      servers = [ "0.nixos.pool.ntp.org" "1.nixos.pool.ntp.org" "2.nixos.pool.ntp.org" "3.nixos.pool.ntp.org" "time.windows.com" "time.google.com" ];
    };
    # Bug in 18.03, timesyncd uses the wrong server list. Fixed in master (https://github.com/NixOS/nixpkgs/pull/40919).
    ntp.servers = [ "0.nixos.pool.ntp.org" "1.nixos.pool.ntp.org" "2.nixos.pool.ntp.org" "3.nixos.pool.ntp.org" "time.windows.com" "time.google.com" ];

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

  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
    cpu.amd.updateMicrocode = true;
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  users.mutableUsers = false;
  # Lock the root user
  users.extraUsers.root = {
    hashedPassword = "!";
  };

  system.autoUpgrade = {
    enable = true;
    dates = "Mon 03:00";
  };

  systemd.services = {

    # Service which runs during the day, to catch the situation where servers
    # are turned off every evening.
    # This service updates and sets the new config as the boot default but
    # does not activate it yet.
    # Mainly copied from  nixpkgs/nixos/modules/installer/tools/auto-upgrade.nix.
    nixos-upgrade-boot = let cfg = config.system.autoUpgrade; in {
      enable = true;
      description = "NixOS Upgrade Boot";
      restartIfChanged = false;
      unitConfig.X-StopOnRemoval = false;
      serviceConfig = {
        User = "root";
        Type = "oneshot";
      };

      environment = config.nix.envVars //
        { inherit (config.environment.sessionVariables) NIX_PATH;
          HOME = "/root";
        } // config.networking.proxy.envVars;

      path = [ pkgs.gnutar pkgs.xz.bin config.nix.package.out ];
      script = ''
        ${config.system.build.nixos-rebuild}/bin/nixos-rebuild boot ${toString cfg.flags}
      '';
      startAt = "Tue 12:00";
    };

    reboot-after-kernel-change = {
      enable = true;
      description = "Reboot the system if the running kernel is different than the kernel of the NixOS current-system.";
      after = [ "nixos-upgrade.service" ];
      wantedBy = [ "nixos-upgrade.service" ];
      restartIfChanged = false;
      unitConfig.X-StopOnRemoval = false;
      serviceConfig = {
        User = "root";
        Type = "oneshot";
      };
      # Check whether the kernel version has been changed and whether we didn't pass 05h00,
      # otherwise we postpone the reboot until the next execution of this service.
      # Current system is the most recently activated system, but its kernel only gets loaded after a reboot.
      # Booted system is the system that we booted in, and whose kernel is thus currently loaded.
      script = ''
        if [ $(dirname $(readlink /run/current-system/kernel)) = $(dirname $(readlink /run/booted-system/kernel)) ]; then
          echo No reboot required.
        elif [ $(date +%s) -gt $(date --date="$(date --date='today' +%Y-%m-%d) + 5 hours" +%s) ]; then
          echo Time window for reboot has passed.
        else
          echo Rebooting...
          systemctl --no-block reboot
        fi
      '';
    };
  };

  nix = {
    autoOptimiseStore = true;
    gc = {
      automatic = true;
      dates = "Tue 03:00";
      options = "--delete-older-than 30d";
    };
  };

  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "18.03"; # Did you read the comment?

}


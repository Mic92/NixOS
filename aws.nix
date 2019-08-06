
########################################################################
#                                                                      #
# DO NOT EDIT THIS FILE, ALL EDITS SHOULD BE DONE IN THE GIT REPO,     #
# PUSHED TO GITHUB AND PULLED HERE.                                    #
#                                                                      #
# LOCAL EDITS WILL BE OVERWRITTEN.                                     #
#                                                                      #
########################################################################

{ config, lib, ... }:

with lib;

{
  imports = [
    <nixpkgs/nixos/modules/virtualisation/amazon-image.nix>
  ];
  ec2.hvm = true;

  settings.boot.mode = "none";
  
  networking = {
    useDHCP = mkForce false;
    nameservers = [ "169.254.169.253" "1.1.1.1" "1.0.0.1" ];
  };

  services.timesyncd.servers = mkForce config.networking.timeServers;
}


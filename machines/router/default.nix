{ config, lib, my-utils, pkgs, ... }:
let
  wanIF = "enp1s0";
  lanIF = "wlp2s0u1";
  lanIP = "10.0.0.1";
in
{
  aquaris = {
    filesystem = { filesystem, zpool, ... }: {
      disks."/dev/disk/by-id/virtio-root".partitions = [
        {
          type = "uefi";
          size = "512M";
          content = filesystem {
            type = "vfat";
            mountpoint = "/boot";
          };
        }
        { content = zpool (p: p.rpool); }
      ];

      zpools.rpool.datasets = {
        "nixos/nix" = { };
        "nixos/persist" = { };
      };
    };
  };

  users.users.admin.openssh.authorizedKeys.keys =
    [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJVieLCkWGImVI9c7D0Z0qRxBAKf0eaQWUfMn0uyM/Ql" ];

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv4.ip_unprivileged_port_start" = 0;
    "net.ipv6.conf.all.disable_ipv6" = 1;
  };

  hardware.firmware = with pkgs; [ ath9k-htc-blobless-firmware ];

  networking = {
    firewall.enable = false;
    networkmanager.enable = lib.mkForce false;

    nameservers = [
      "1.1.1.1#one.one.one.one"
      "1.0.0.1#one.one.one.one"

      "9.9.9.9#dns.quad9.net"
      "149.112.112.112#dns.quad9.net"
    ];

    interfaces = {
      ${wanIF}.useDHCP = true;
      ${lanIF} = {
        useDHCP = false;
        ipv4.addresses = [{
          address = lanIP;
          prefixLength = 24;
        }];
      };
    };

    nftables = {
      enable = true;
      ruleset = my-utils.subsT ./firewall.nft {
        wan = wanIF;
        lan = lanIF;
      };
    };
  };

  systemd.network.wait-online.enable = lib.mkForce true;

  services = {
    kea.dhcp4 = {
      enable = true;
      settings = {
        interfaces-config.interfaces = [ lanIF ];
        subnet4 = [{
          subnet = "10.0.0.0/24";
          pools = [{ pool = "10.0.0.2 - 10.0.0.254"; }];
          option-data = [
            { name = "routers"; data = lanIP; }
            { name = "domain-name-servers"; data = lanIP; }
          ];
        }];
      };
    };

    resolved = {
      llmnr = "false";
      dnssec = "true";
      dnsovertls = "true";
      fallbackDns = [ ];
      extraConfig = ''
        DNSStubListenerExtra=${lanIP}
      '';
    };

    hostapd = {
      enable = true;
      radios.${lanIF} = {
        networks.${lanIF} = {
          ssid = "Infernum";
          authentication.saePasswordsFile =
            config.aquaris.secrets."machine/sae-password".outPath;
        };
      };
    };
  };
}

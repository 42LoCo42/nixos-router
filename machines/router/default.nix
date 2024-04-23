{ config, lib, my-utils, pkgs, ... }:
let
  wanIF = "enp1s0";
  lanIF = "wlp2s0u1";
  lanIP = "10.0.0.1";

  netbootxyz-kpxe =
    let
      src = pkgs.fetchurl {
        url = "https://github.com/netbootxyz/netboot.xyz/releases/download/2.0.78/netboot.xyz.kpxe";
        hash = "sha256-pWbhaS3m4kMOlCH8MyDlX7mM6y0udCxYQAVw9al6Jxs=";
      };
    in
    pkgs.runCommand "netbootxyz-kpxe" { } ''
      install -Dm444 "${src}" "$out/netboot.xyz.kpxe"
    '';
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

    persist.system = [
      "/var/lib/dnsmasq"
      "/var/lib/systemd"
    ];
  };

  users.users.admin.openssh.authorizedKeys.keys =
    [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJVieLCkWGImVI9c7D0Z0qRxBAKf0eaQWUfMn0uyM/Ql" ];

  boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true;

  hardware.firmware = with pkgs; [ ath9k-htc-blobless-firmware ];

  networking = {
    useDHCP = false;
    firewall.enable = false;
    networkmanager.enable = lib.mkForce false;

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
  systemd.services.dnsmasq.after = [ "network-online.target" ];

  services = {
    resolved.enable = false;

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

    stubby = {
      enable = true;
      settings = pkgs.stubby.settingsExample // {
        listen_addresses = [ "127.0.0.1@53000" ];
        dnssec_return_status = "GETDNS_EXTENSION_TRUE";
        upstream_recursive_servers = [
          { address_data = "1.1.1.1"; tls_port = 853; tls_auth_name = "cloudflare-dns.com"; }
          { address_data = "1.0.0.1"; tls_port = 853; tls_auth_name = "cloudflare-dns.com"; }
          { address_data = "9.9.9.9"; tls_port = 853; tls_auth_name = "dns.quad9.net"; }
          { address_data = "149.112.112.112"; tls_port = 853; tls_auth_name = "dns.quad9.net"; }
        ];
      };
    };

    dnsmasq = {
      enable = true;
      settings = {
        # listen on localhost and LAN
        interface = lanIF;
        bind-interfaces = true;
        listen-address = [ "127.0.0.1" lanIP ];

        # forward to stubby
        no-resolv = true;
        server = [ "127.0.0.1#53000" ];

        # misc
        cache-size = 10000;
        proxy-dnssec = true;
        log-queries = true;

        # local domain
        local = "/lan/";
        domain = "lan";

        # DHCP
        dhcp-range = "10.0.0.2,10.0.0.254,12h";
        dhcp-option = [
          "option:router,${lanIP}"
          "option:dns-server,${lanIP}"
          "option:tftp-server,${lanIP}"
        ];

        # netboot.xyz
        enable-tftp = true;
        tftp-root = netbootxyz-kpxe.outPath;
        dhcp-boot = "netboot.xyz.kpxe";
      };
    };
  };
}

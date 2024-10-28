{ pkgs, lib, config, ... }:
let
  inherit (lib) mkIf mkMerge mkOption;
  inherit (lib.types) bool path str;

  cfg = config.services.router;
in
{
  options.services.router = {
    enable = mkOption {
      description = "Enable the router service";
      type = bool;
      default = false;
    };

    lanIF = mkOption {
      description = "LAN (internal) interface";
      type = str;
    };

    wanIF = mkOption {
      description = "WAN (external) interface";
      type = str;
    };

    lanIP = mkOption {
      description = "LAN IP of the router";
      type = str;
      default = "10.0.0.1";
    };

    lanSize = mkOption {
      description = "Size of the LAN in CIDR notation";
      type = lib.types.ints.between 0 32;
      default = 24;
    };

    lanAlloc = mkOption {
      description = "DHCP allocation range & duration";
      type = str;
      default = "10.0.0.2,10.0.0.254,12h";
    };

    blockFakeLocals = mkOption {
      description = "Block WAN connections from local IPs";
      type = bool;
      default = true;
    };

    wlan = {
      enable = mkOption {
        description = "Enable the WLAN";
        type = bool;
        default = true;
      };

      ssid = mkOption {
        description = "SSID of the WLAN";
        type = str;
      };

      passwordFile = mkOption {
        description = "Path to the SAE password file";
        type = path;
      };

      hide = mkOption {
        description = "Hide the WLAN";
        type = bool;
        default = false;
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      networking = {
        useDHCP = false;

        interfaces = {
          ${cfg.wanIF}.useDHCP = true;
          ${cfg.lanIF} = {
            useDHCP = false;
            ipv4.addresses = [{
              address = cfg.lanIP;
              prefixLength = cfg.lanSize;
            }];
          };
        };

        nftables.enable = true;

        firewall = {
          allowPing = false;
          filterForward = true;
          trustedInterfaces = [ cfg.lanIF ];

          extraInputRules = mkIf cfg.blockFakeLocals ''
            iifname "${cfg.wanIF}" ip saddr \
            { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }
          '';
        };

        nat = {
          enable = true;
          externalInterface = cfg.wanIF;
          internalInterfaces = [ cfg.lanIF ];
        };
      };

      services = {
        resolved.enable = false;

        dnsmasq = {
          enable = true;
          settings = {
            interface = cfg.lanIF;
            bind-interfaces = true;
            listen-address = [ "127.0.0.1" cfg.lanIF ];

            # forward to stubby
            server = [ "127.0.0.1#53000" ];

            # local domain
            domain = "lan";
            local = "/lan/";

            # DHCP
            dhcp-range = cfg.lanAlloc;
            dhcp-option = [
              "option:router,${cfg.lanIP}"
              "option:dns-server,${cfg.lanIP}"
            ];

            # misc
            cache-size = 10000;
            filter-AAAA = true;
            log-queries = true;
            proxy-dnssec = true;
          };
        };

        stubby = {
          enable = true;
          logLevel = "info";
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
      };
    }

    (mkIf (config ? "aquaris.persist") {
      aquaris.persist = {
        enable = true;
        dirs = [ "/var/lib/dnsmasq" ];
      };
    })

    (mkIf cfg.wlan.enable {
      services.hostapd = {
        enable = true;
        radios.${cfg.lanIF} = {
          channel = 6;

          networks.default = {
            inherit (cfg.wlan) ssid;
            authentication.saePasswordsFile = cfg.wlan.passwordFile;
            ignoreBroadcastSsid = mkIf cfg.wlan.hidden "empty";
          };
        };
      };

      systemd.services = {
        dnsmasq = {
          after = [ "hostapd.service" ];
          wants = [ "hostapd.service" ];
        };

        hostapd.serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/sleep 10";
      };

      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "qr";
          runtimeInputs = with pkgs; [ openssl qrtool ];
          text =
            let fmt = ''WIFI:T:WPA;R:3;S:${cfg.wlan.ssid};P:'"$passwd"';K:\1;;''; in
            ''
              src="''${1-${cfg.wlan.passwordFile}}"

              passwd="$(grep -oP '^[^|#]+' "$src")"
              seckey="$(grep -oP 'pk=[^:]+:\K[^|]+' "$src")"

              <<< "$seckey"             \
              base64 -d                 \
              | openssl ec              \
                -inform der             \
                -pubout                 \
                -conv_form compressed   \
                -outform der            \
              | base64 -w0              \
              | sed -E 's|(.*)|${fmt}|' \
              | qrtool encode -t unicode
            '';
        })
      ];
    })
  ]);
}

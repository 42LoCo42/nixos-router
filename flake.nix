{
  inputs = {
    aquaris.url = "github:42loco42/aquaris";
    aquaris.inputs.home-manager.follows = "home-manager";
    aquaris.inputs.nixpkgs.follows = "nixpkgs";
    aquaris.inputs.obscura.follows = "obscura";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    obscura.url = "github:42loco42/obscura";
    obscura.inputs.nce.follows = "";
    obscura.inputs.nsc.follows = "";
  };

  outputs = { self, aquaris, ... }:
    let
      users = {
        "admin" = {
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC3zQ1L8EgMHz6twDbYyyHkfK2b3MsiuCbI09iYfe4sS";
        };
      };
      machines = {
        "router" = {
          id = "f2f78bb638744df090ed8818bdb922f7";
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID4OB/wSEd+uH2jWQbkmL2EG8Ri8NdbqhxKO8HiKCvXV";
          admins = { inherit (users) "admin"; };
          users = { };
        };
      };
    in
    aquaris.lib.main self { inherit users machines; };
}

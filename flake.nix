{
  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys = [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
    allow-import-from-derivation = "true";
  };

  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Owned by this flake so the flake-compat node in flake.lock (used by
    # default.nix/shell.nix) does not disappear if haskell.nix drops it.
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      haskellNix,
      flake-utils,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    in
    flake-utils.lib.eachSystem supportedSystems (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          inherit (haskellNix) config;
          overlays = [ haskellNix.overlay ];
        };

        project = pkgs.haskell-nix.cabalProject' {
          src = ./.;
          compiler-nix-name = "ghc9103";
        };

        flake = project.flake { };
      in
      {
        inherit (flake) checks;

        packages = flake.packages // {
          default = flake.packages."webauthn:lib:webauthn";
        };

        apps = flake.apps // {
          deploy = {
            type = "app";
            program = "${pkgs.writeShellScript "deploy" ''
              ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch \
                --build-host localhost \
                --target-host webauthn.dev.tweag.io \
                --use-remote-sudo --no-build-nix \
                --flake ${self.outPath}#webauthn-server
            ''}";
          };
        };

        devShells = flake.devShells // {
          default = project.shellFor {
            tools = {
              cabal = "latest";
              haskell-language-server = "latest";
              hlint = "latest";
              ormolu = "latest";
            };
            buildInputs = with pkgs; [
              entr
              gitMinimal
              python3
              yarn
              nodejs
              jq
              zlib
              pkg-config
              haskellPackages.cabal-plan
            ];
          };
        };
      }
    )
    // {
      nixosConfigurations.webauthn-server = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./infra/configuration.nix
        ];
      };
    };
}

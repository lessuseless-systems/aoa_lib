{
  description = "Agent Orchestrator Project — Flake with Nickel, Organist, PocketFlow, BitNet Workers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";

    # Nickel language
    nickel.url = "github:nickel-lang/nickel";

    # Nickel Organist (template/CLI runner)
    organist.url = "github:nickel-lang/organist";

    # PocketFlow template (Rust project)
    pocketflow.url = "github:your-org/pocketflow-template-rust"; # replace with real repo

    # BitNet workers (Rust/gguf integration)
    bitnet-workers.url = "github:your-org/bitnet-workers"; # replace with real repo
  };

  outputs = { self, nixpkgs, flake-utils, nickel, organist, pocketflow, bitnet-workers, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {

        ###########################################
        ## Development Shell
        ###########################################
        devShell = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            # languages & build tools
            rustc cargo rustfmt clippy
            pkg-config
            openssl.dev

            # Nickel
            nickel.packages.${system}.default
            organist.packages.${system}.default

            # JSON / YAML tooling
            jq yq

            # Nushell (glue layer)
            nushell

            # Nix helpers
            nil alejandra
          ];

          # environment variables
          RUST_LOG = "info";
          POCKETFLOW_MODEL_DIR = "${bitnet-workers}/models";
        };

        ###########################################
        ## Packages
        ###########################################
        packages = {
          # PocketFlow compiled binary
          pocketflow = pkgs.rustPlatform.buildRustPackage {
            pname = "pocketflow";
            version = "0.1.0";
            src = pocketflow;
            cargoLock = {
              lockFile = pocketflow + "/Cargo.lock";
            };
          };

          # BitNet worker binary
          bitnet-worker = pkgs.rustPlatform.buildRustPackage {
            pname = "bitnet-worker";
            version = "0.1.0";
            src = bitnet-workers;
            cargoLock = {
              lockFile = bitnet-workers + "/Cargo.lock";
            };
          };
        };

        ###########################################
        ## Apps (CLI entrypoints)
        ###########################################
        apps = {
          pocketflow = {
            type = "app";
            program = self.packages.${system}.pocketflow + "/bin/pocketflow";
          };

          bitnet-worker = {
            type = "app";
            program = self.packages.${system}.bitnet-worker + "/bin/bitnet-worker";
          };

          organist = {
            type = "app";
            program = organist.packages.${system}.default + "/bin/organist";
          };
        };

        ###########################################
        ## Formatter
        ###########################################
        formatter = pkgs.alejandra;
      });
  # --- treefmt integration ---
  treefmt-nix = inputs.treefmt-nix;

  formatter = treefmt-nix.lib.mkNode {
    projectRoot = self;
    programs = {
      nixfmt.enable = true;
      prettier.enable = true;
    };
  };
}

{
  description = "hashbrown fork (usrbinkat/hashbrown): the toolchains its CI checks run on";

  # Fork-only file, like AGENTS.md: it pins what ci/tools.sh, ci/run.sh,
  # ci/miri.sh and .github/workflows/rust.yml run, so every check of the
  # fork runs locally on pinned toolchains. Not part of any upstream
  # contribution.

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    konductor = {
      url = "github:braincraftio/konductor";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      konductor,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [
            konductor.inputs.rust-overlay.overlays.default
            konductor.overlays.default
          ];
        };
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          # ci/tools.sh lints every target with a dedicated SIMD
          # implementation plus one generic target, since cfg-disabled code
          # is never linted: SSE2, NEON, LSX, and i586 for the generic group.
          lintTargets = [
            "x86_64-unknown-linux-gnu"
            "aarch64-unknown-linux-gnu"
            "loongarch64-unknown-linux-gnu"
            "i586-unknown-linux-gnu"
          ];
          # The nightly the forked standard library (usrbinkat/rust,
          # feat/bounded-collection-access) is built from, rust-lang/rust
          # db8f076: the compiler this crate meets when vendored into std.
          # It runs the nightly-feature clippy pass, Miri (ci/miri.sh) and the
          # dep_of_std build (rust.yml).
          nightly = pkgs.rust-bin.nightly."2026-10-04".default.override {
            extensions = [
              "rust-src"
              "clippy"
              "rustfmt"
              "miri"
            ];
            targets = lintTargets;
          };
          # The stable release the rest of the workspace pins; ci/tools.sh's
          # stable clippy pass and ci/run.sh's stable channel.
          stable = pkgs.rust-bin.stable."1.98.1".default.override {
            extensions = [
              "rust-src"
              "clippy"
              "rustfmt"
            ];
            targets = lintTargets;
          };
          # Cargo.toml rust-version; ci/run.sh's 1.85.0 channel. rust.yml's
          # msrv job (cargo msrv verify) is covered by running ci/run.sh in
          # this shell, which builds and tests on this pinned toolchain;
          # cargo-msrv itself installs toolchains through rustup, outside
          # the pinned set, so it is not part of the shell.
          msrv = pkgs.rust-bin.stable."1.85.0".default;
          # ci/tools.sh runs taplo and shellcheck when present.
          tools = [
            pkgs.taplo
            pkgs.shellcheck
          ];
          shell =
            toolchain:
            pkgs.mkShell {
              nativeBuildInputs = [ toolchain ] ++ tools;
              RUSTC = pkgs.lib.getExe' toolchain "rustc";
              RUSTDOC = pkgs.lib.getExe' toolchain "rustdoc";
              RUSTFMT = pkgs.lib.getExe' toolchain "rustfmt";
              # The selected toolchain first, so no cargo, rustc or
              # clippy-driver from an enclosing environment or the cargo home
              # directory precedes it.
              shellHook = ''
                export PATH="${toolchain}/bin:$PATH"
              '';
            };
        in
        {
          default = shell nightly;
          nightly = shell nightly;
          stable = shell stable;
          msrv = shell msrv;
        }
      );
    };
}

{
  description = "Native Serpantinum world-clock module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.serpantinum.url = "github:ilyamiro/serpantinum/44d33831ab6314e7d2d7f0323c1fc023cb08804c";

  outputs = { self, nixpkgs, serpantinum }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in {
      packages = forAllSystems (pkgs:
        let
          backend = import ./backend.nix { inherit pkgs; };
          patchedSerpantinum = import ./default.nix {
            inherit pkgs backend;
            serpantinum = serpantinum.packages.${pkgs.system}.default;
          };
        in {
          inherit backend patchedSerpantinum;
          default = backend;
        });

      checks = forAllSystems (pkgs: {
        backend = self.packages.${pkgs.system}.backend;
        patcher = pkgs.runCommand "world-clock-patcher-tests" {
          nativeBuildInputs = [ pkgs.python3 ];
        } ''
          cp -r ${./.} source
          chmod -R u+w source
          mkdir serpantinum-root
          cp ${serpantinum.outPath}/version.txt serpantinum-root/version.txt
          cp -r ${serpantinum.outPath}/src/. serpantinum-root/
          chmod -R u+w serpantinum-root
          cd source
          python -m unittest discover -s tests -p 'test_*.py'
          python scripts/patch_serpantinum.py --root ../serpantinum-root \
            --expected-version 2.1.0 \
            --expected-revision 44d33831ab6314e7d2d7f0323c1fc023cb08804c
          python scripts/patch_serpantinum.py --root ../serpantinum-root \
            --expected-version 2.1.0 \
            --expected-revision 44d33831ab6314e7d2d7f0323c1fc023cb08804c
          python -m json.tool ../serpantinum-root/assets/languages/en.json >/dev/null
          touch $out
        '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            cargo
            clippy
            nixfmt-rfc-style
            python3
            rustc
            rustfmt
            qt6.qtdeclarative
            qt6.qtshadertools
          ];
        };
      });

      lib.patchSerpantinum = { pkgs, serpantinum }:
        import ./default.nix {
          inherit pkgs serpantinum;
        };
    };
}

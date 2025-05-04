{
  description = "Burrito guild wars 2 overlay";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      src = pkgs.fetchzip {
        url = "https://github.com/AsherGlick/Burrito/releases/download/burrito-1.0.0/burrito-1.0.0.zip";
        stripRoot = false;
        sha256 = "10iz1w3vz1881i8h898v2ankhfhcsi439jh8b38z14jpfzbv2m6x";
      };
      buildInputs = with pkgs; [
        stdenv.cc.cc.lib
        glibc
        gcc
        xorg.libXcursor
        xorg.libX11
        xorg.libXinerama
        xorg.libXext
        xorg.libXrandr
        xorg.libXrender
        xorg.libXi
        libGL
        libudev-zero
      ];
    in
    {
      packages.${system} = {
        default = self.packages.${system}.burrito-fhs;

        burrito-fhs = pkgs.buildFHSUserEnv {
          name = "burrito-gw2";

          targetPkgs = _: buildInputs;
          runScript = "${self}/script.sh ${src}";
        };

        # branch to build from release files
        # for history
        burrito-release = pkgs.stdenv.mkDerivation {
          name = "burrito";
          version = "1.0.0";

          src = src;

          nativeBuildInputs = [
            pkgs.makeWrapper
            pkgs.patchelf
          ];

          buildInputs = buildInputs;

          # Unpack and make writable
          unpackPhase = ''
            cp -r $src source
            chmod -R +w source
            sourceRoot=source
          '';

          installPhase = ''
            # Create directory structure
            mkdir -p $out/bin $out/share/burrito

            # Copy everything to share directory with proper permissions
            cp -r ./* $out/share/burrito/

            # Ensure everything is accessible
            chmod -R +rw $out/share/burrito

            # Make executables executable
            chmod +x $out/share/burrito/burrito.x86_64
            chmod +x $out/share/burrito/xml_converter

            # Patch only the interpreter path
            patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
              $out/share/burrito/burrito.x86_64

            # Create wrapper script
            makeWrapper "$out/share/burrito/burrito.x86_64" "$out/bin/burrito" \
              --prefix LD_LIBRARY_PATH : "$out/share/burrito:${pkgs.lib.makeLibraryPath buildInputs}" \
              --run "cd $out/share/burrito"
          '';

          meta = {
            description = "Burrito guild wars 2 overlay";
            platforms = [ "x86_64-linux" ];
          };
        };
      };

      devShell.${system} = pkgs.mkShell {
        buildInputs = [
          self.packages.${system}.burrito-fhs
          self.packages.${system}.burrito-release
        ];
      };
    };
}

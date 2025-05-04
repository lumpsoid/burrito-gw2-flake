{
  description = "Burrito guild wars 2 overlay";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        overlays = [(import rust-overlay)];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        # Common dependencies
        stdenv = pkgs.stdenv;
        lib = pkgs.lib;

        # Source for the project
        src = pkgs.fetchFromGitHub {
          owner = "AsherGlick";
          repo = "Burrito";
          rev = "0aac9e4ad612665396158c00f288c6644ea20b4b";
          sha256 = "sha256-W9AUIuzHkOLXr/Vtch6oMEvDZzNydU80WmW1qqOAT2o=";
          fetchSubmodules = true;
        };

        # Rust toolchain for burrito-fg and taco_parser
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          targets = ["x86_64-unknown-linux-gnu"];
        };

        # Build dependencies
        buildDeps = with pkgs; [
          # C++ build tools
          cmake
          gcc
          pkg-config
          gtest
          protobuf

          # Python deps for burrito_converter
          # probably not needed?
          (python3.withPackages (ps:
            with ps; [
              pip
              venv
            ]))

          # For Godot
          unzip

          # For Windows builds
          mingw-w64
        ];

        # Runtime dependencies
        runtimeDeps = with pkgs; [
          stdenv.cc.cc.lib
          glibc
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

        # Build the burrito_converter component
        burrito_converter = stdenv.mkDerivation {
          pname = "burrito_converter";
          version = "1.0.0";
          inherit src;

          sourceRoot = "source/burrito_converter";

          # Add specific CMake flags to help find Protobuf
          cmakeFlags = [
            "-DProtobuf_INCLUDE_DIR=${pkgs.protobuf}/include"
            "-DProtobuf_LIBRARY=${pkgs.protobuf}/lib/libprotobuf.so"
            "-DProtobuf_PROTOC_EXECUTABLE=${pkgs.protobuf}/bin/protoc"
          ];

          # dependencies at build time
          nativeBuildInputs = with pkgs; [
            cmake
            gcc
            pkg-config
            protobuf
            gtest
            python3Packages.pip # probably not needed
            # cpplint  # failing with internal test errors
          ];

          buildPhase = ''
            mkdir -p build
            cd build
            cmake ..
            make -j $NIX_BUILD_CORES
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp burrito_converter $out/bin/
            chmod +x $out/bin/burrito_converter
          '';
        };

        # Build the burrito_link component
        burrito_link = stdenv.mkDerivation {
          pname = "burrito_link";
          version = "1.0.0";
          inherit src;

          sourceRoot = "source/burrito_link";

          cmakeFlags = [
            # Configure CMake to use the MinGW cross compiler
            "-DCMAKE_SYSTEM_NAME=Windows"
            "-DCMAKE_C_COMPILER=${pkgs.pkgsCross.mingwW64.buildPackages.gcc}/bin/x86_64-w64-mingw32-gcc"
            "-DCMAKE_CXX_COMPILER=${pkgs.pkgsCross.mingwW64.buildPackages.gcc}/bin/x86_64-w64-mingw32-g++"
            # Switch to win32 thread model to avoid mcfgthreads dependency
            "-DCMAKE_C_FLAGS=-mthreads"
            "-DCMAKE_CXX_FLAGS=-mthreads"
          ];

          # dependencies at build time
          nativeBuildInputs = with pkgs; [
            cmake

            # For Windows builds - replace mingw-w64 with cross compiler
            pkgsCross.mingwW64.buildPackages.gcc
          ];

          buildPhase = ''
            mkdir -p build
            cd build
            cmake ..
            make -j $NIX_BUILD_CORES
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp burrito_link.exe $out/bin/
            cp d3d11.dll $out/bin/
            cp arcdps_burrito_link.dll $out/bin/
          '';
        };

        # Build the burrito-fg component
        burrito_fg = pkgs.rustPlatform.buildRustPackage {
          pname = "burrito-fg";
          version = "1.0.0";
          inherit src;

          sourceRoot = "source/burrito-fg";

          cargoHash = ""; # Replace with the correct hash

          # dependencies at build time
          nativeBuildInputs = [rustToolchain];

          postInstall = ''
            mkdir -p $out/lib
            cp target/release/libburrito_fg.so $out/lib/
          '';
        };

        # Build the taco_parser component
        taco_parser = pkgs.rustPlatform.buildRustPackage {
          pname = "taco-parser";
          version = "1.0.0";
          inherit src;

          sourceRoot = "source/taco_parser";

          cargoHash = ""; # Replace with the correct hash

          # dependencies at build time
          nativeBuildInputs = [rustToolchain];

          postInstall = ''
            mkdir -p $out/lib
            cp target/release/libgw2_taco_parser.so $out/lib/
          '';
        };

        # Godot version from the workflow
        godotVersion = "3.3.2";

        godot_headless = stdenv.mkDerivation {
          pname = "godot-headless";
          version = godotVersion;
          dontUnpack = true;
          nativeBuildInputs = [pkgs.unzip pkgs.curl pkgs.patchelf];
          SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";

          buildPhase = ''
            curl -Lo godot.zip https://github.com/godotengine/godot/releases/download/${godotVersion}-stable/Godot_v${godotVersion}-stable_linux_headless.64.zip
            unzip godot.zip
            chmod +x Godot_v${godotVersion}-stable_linux_headless.64
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp Godot_v${godotVersion}-stable_linux_headless.64 $out/bin/

            # Patch the interpreter path
            patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/bin/Godot_v${godotVersion}-stable_linux_headless.64
          '';
        };

        godot_templates = stdenv.mkDerivation {
          pname = "godot-templates";
          version = godotVersion;
          dontUnpack = true;
          nativeBuildInputs = [pkgs.unzip pkgs.curl];
          SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";

          buildPhase = ''
            curl -Lo templates.tpz https://github.com/godotengine/godot/releases/download/${godotVersion}-stable/Godot_v${godotVersion}-stable_export_templates.tpz
            unzip templates.tpz
          '';

          installPhase = ''
            mkdir -p $out/templates/${godotVersion}.stable/
            mv templates/* $out/templates/${godotVersion}.stable/
          '';
        };

        # Build the Burrito UI component with Godot
        burrito_ui = stdenv.mkDerivation {
          pname = "burrito-ui";
          version = "1.0.0";
          inherit src;

          # dependencies at build time
          nativeBuildInputs = with pkgs; [
            unzip
            curl

            # Debugging tools
            file
            ldd
            strace
          ];

          # for curl
          # because of
          # curl: (77) error setting certificate file: /no-cert-file.crt
          # https://github.com/NixOS/nixpkgs/issues/13744#issuecomment-198779626
          SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";

          buildPhase = ''
                # Create fake GDNative files structure
                mkdir -p burrito-fg/target/release/
                touch burrito-fg/target/release/libburrito_fg.so
                mkdir -p taco_parser/target/release/
                touch taco_parser/target/release/libgw2_taco_parser.so

                # Use pre-downloaded Godot
                mkdir -p build
                cp ${godot_headless}/bin/Godot_v${godotVersion}-stable_linux_headless.64 .

                # Create local templates directory
                mkdir -p .local/share/godot/templates/${godotVersion}.stable/
                cp -r ${godot_templates}/templates/${godotVersion}.stable/* .local/share/godot/templates/${godotVersion}.stable/

                # Set XDG_DATA_HOME
                export XDG_DATA_HOME="$PWD/.local"

                # Debug Godot binary
                echo "File information:"
                file ./Godot_v${godotVersion}-stable_linux_headless.64

                echo "Library dependencies:"
                ldd ./Godot_v${godotVersion}-stable_linux_headless.64 || echo "ldd failed"

                echo "Trying to run with strace to see missing dependencies:"
                strace -f ./Godot_v${godotVersion}-stable_linux_headless.64 --version || echo "Strace failed"

            # ERROR NEEDED TO BE ADDRESSED
                        # ./Godot_v3.3.2-stable_linux_headless.64: cannot execute: required file not found

                # Try export command
                echo "Attempting to export project:"
                ./Godot_v${godotVersion}-stable_linux_headless.64 --export "Linux/X11" build/burrito.x86_64 || echo "Export failed"
          '';

          installPhase = ''
            mkdir -p $out/bin
            if [ -f build/burrito.x86_64 ]; then
              cp build/burrito.x86_64 $out/bin/
            else
              echo "Build failed, creating placeholder for debugging"
              touch $out/bin/burrito.x86_64
            fi
          '';
          # Don't fail the build so we can see debug output
          dontFixup = true;
        };

        # The final package combining all components
        burrito = stdenv.mkDerivation {
          pname = "burrito";
          version = "1.0.0";

          phases = ["installPhase"];

          installPhase = ''
            mkdir -p $out/bin $out/lib

            # Copy burrito_converter
            cp ${burrito_converter}/bin/burrito_converter $out/bin/

            # Copy burrito_link files
            mkdir -p $out/share/burrito_link
            cp ${burrito_link}/bin/burrito_link.exe $out/share/burrito_link/
            cp ${burrito_link}/bin/d3d11.dll $out/share/burrito_link/
            cp ${burrito_link}/bin/arcdps_burrito_link.dll $out/share/burrito_link/

            # Copy burrito UI
            cp ${burrito_ui}/bin/burrito.x86_64 $out/bin/

            # Copy libraries
            cp ${burrito_fg}/lib/libburrito_fg.so $out/lib/
            cp ${taco_parser}/lib/libgw2_taco_parser.so $out/lib/

            # Create wrapper script
            cat > $out/bin/burrito <<EOF
            #!/bin/sh
            cd $out/bin
            exec ./burrito.x86_64
            EOF
            chmod +x $out/bin/burrito
          '';

          meta = {
            description = "Burrito Guild Wars 2 overlay";
            platforms = ["x86_64-linux"];
          };
        };

        # FHS environment for running the app
        burrito-fhs = pkgs.buildFHSUserEnv {
          name = "burrito-gw2";
          targetPkgs = pkgs: runtimeDeps;
          runScript = "${burrito}/bin/burrito";
        };
      in {
        packages = {
          inherit burrito burrito_converter burrito_link burrito_fg taco_parser burrito_ui burrito-fhs;
          inherit godot_headless godot_templates;
          default = burrito-fhs;
        };

        devShells = {
          default = pkgs.mkShell {
            buildInputs =
              buildDeps
              ++ runtimeDeps
              ++ [
                rustToolchain
              ];
          };

          debugShell = pkgs.mkShell {
            buildInputs = with pkgs; [
              # All possible runtime dependencies for Godot
              xorg.libX11
              xorg.libXcursor
              xorg.libXinerama
              xorg.libXext
              xorg.libXrandr
              xorg.libXrender
              xorg.libXi
              libGL
              zlib
              alsa-lib
              pulseaudio
              libudev-zero
              freetype

              # Debug tools
              glibc  # ldd
              file
              strace

              # Original build dependencies
              unzip
              curl
            ];

            shellHook = ''
              echo "Debugging environment for Godot headless"
              echo "To debug the Godot binary, run:"
              echo "ldd ${godot_headless}/bin/Godot_v${godotVersion}-stable_linux_headless.64"
              echo "file ${godot_headless}/bin/Godot_v${godotVersion}-stable_linux_headless.64"
              echo "strace ${godot_headless}/bin/Godot_v${godotVersion}-stable_linux_headless.64 --version"
            '';
          };
        };
      }
    );
}

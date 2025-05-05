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
        rustTarget = "x86_64-unknown-linux-gnu";
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          targets = [rustTarget];
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
            ]))

          # For Godot
          unzip
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
          # would be passed to cmake
          # https://discourse.nixos.org/t/cmakeflags-and-spaces-in-option-values/20170
          cmakeFlags = [
            "-DProtobuf_INCLUDE_DIR=${pkgs.protobuf}/include"
            "-DProtobuf_LIBRARY=${pkgs.protobuf}/lib/libprotobuf.so"
            "-DProtobuf_PROTOC_EXECUTABLE=${pkgs.protobuf}/bin/protoc"
            "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
          ];

          # dependencies at build time
          nativeBuildInputs = with pkgs; [
            cmake
            gcc
            pkg-config
            protobuf
            gtest
            python3Packages.pip
            # cpplint  # failing with internal test errors
          ];

          buildPhase = ''
            cmake .
            make -j $NIX_BUILD_CORES
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp burrito_converter $out/bin/
            chmod +x $out/bin/burrito_converter
          '';
        };

        # Build the burrito_link component
        burrito_link = let
          # Create a gcc wrapper that uses win32 threads instead of posix
          # https://discourse.nixos.org/t/statically-linked-mingw-binaries/38395/7
          gcc = pkgs.pkgsCross.mingwW64.buildPackages.wrapCC (pkgs.pkgsCross.mingwW64.buildPackages.gcc-unwrapped.override {
            threadsCross = {
              model = "win32";
              package = null;
            };
          });

          # Create a new stdenv with our custom gcc
          customStdenv = pkgs.overrideCC pkgs.pkgsCross.mingwW64.stdenv gcc;
        in
          customStdenv.mkDerivation
          {
            pname = "burrito_link";
            version = "1.0.0";
            inherit src;

            sourceRoot = "source/burrito_link";

            nativeBuildInputs = with pkgs; [
              cmake
            ];

            buildPhase = ''
              cmake ..
              make -j $NIX_BUILD_CORES
            '';

            installPhase = ''
              mkdir -p $out/bin

              # for some reason it named as burrito_link.exe.exe
              cp burrito_link.exe.exe $out/bin/burrito_link.exe

              cp d3d11.dll $out/bin/

              # https://github.com/AsherGlick/Burrito/blob/0aac9e4ad612665396158c00f288c6644ea20b4b/.github/workflows/main.yml#L122
              cp d3d11.dll $out/bin/arcdps_burrito_link.dll
            '';
          };

        # Build the burrito-fg component
        burrito_fg = pkgs.rustPlatform.buildRustPackage {
          pname = "burrito-fg";
          version = "1.0.0";
          inherit src;

          sourceRoot = "source/burrito-fg";

          cargoHash = "sha256-2+xx/OL1Xuxy15IxVQUpo4f/PNVkwL7i/gdWe5FyRLw=";

          # dependencies at build time
          nativeBuildInputs = [
            rustToolchain
            pkgs.clang
            pkgs.llvmPackages.libclang
          ];

          LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";

          # Skip running tests
          doCheck = false;

          postInstall = ''
            mkdir -p $out/lib
            cp target/${rustTarget}/release/libburrito_fg.so $out/lib/
          '';
        };

        # Build the taco_parser component
        taco_parser = pkgs.rustPlatform.buildRustPackage {
          pname = "taco-parser";
          version = "1.0.0";
          inherit src;

          sourceRoot = "source/taco_parser";

          cargoHash = "sha256-p/kX1iuMIbCj5OSKG5PMZqhayvqIAAARy8De/am4/3Q=";

          # dependencies at build time
          nativeBuildInputs = [
            rustToolchain
            pkgs.clang
            pkgs.llvmPackages.libclang
          ];

          LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";

          postInstall = ''
            mkdir -p $out/lib
            cp target/${rustTarget}/release/libgw2_taco_parser.so $out/lib/
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
            gnused
          ];

          # for curl
          # because of
          # curl: (77) error setting certificate file: /no-cert-file.crt
          # https://github.com/NixOS/nixpkgs/issues/13744#issuecomment-198779626
          SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";

          buildPhase = ''
            # Create GDNative files structure
            mkdir -p burrito-fg/target/release/
            touch burrito-fg/target/release/libburrito_fg.so
            mkdir -p taco_parser/target/release/
            touch taco_parser/target/release/libgw2_taco_parser.so

            # Create project-local config directory to avoid homeless-shelter issue
            mkdir -p .config/godot/projects

            # Use pre-downloaded Godot
            mkdir -p build
            cp ${godot_headless}/bin/Godot_v${godotVersion}-stable_linux_headless.64 .

            # Create proper template directory structure
            mkdir -p .local/share/godot/templates/${godotVersion}.stable/
            cp -r ${godot_templates}/templates/${godotVersion}.stable/* .local/share/godot/templates/${godotVersion}.stable/

            # Create symbolic links for the expected template paths
            mkdir -p .local/godot/templates/${godotVersion}.stable/
            ln -s $PWD/.local/share/godot/templates/${godotVersion}.stable/linux_x11_64_debug .local/godot/templates/${godotVersion}.stable/
            ln -s $PWD/.local/share/godot/templates/${godotVersion}.stable/linux_x11_64_release .local/godot/templates/${godotVersion}.stable/

            # Set up environment variables
            export HOME=$PWD
            export XDG_CONFIG_HOME="$PWD/.config"
            export XDG_DATA_HOME="$PWD/.local/share"

            # Modify export_presets.cfg to set embed_pck=false
            sed -i 's/binary_format\/embed_pck=true/binary_format\/embed_pck=false/g' export_presets.cfg

            ./Godot_v${godotVersion}-stable_linux_headless.64 --export "Linux/X11"
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp build/burrito.x86_64 $out/bin/
            cp build/burrito.pck $out/bin/
          '';
        };

        # The final package combining all components
        burrito = stdenv.mkDerivation {
          pname = "burrito";
          version = "1.0.0";

          phases = ["installPhase"];

          # at this point don't really sure
          # that this is needed
          nativeBuildInputs = [pkgs.makeWrapper];

          installPhase = ''
            mkdir -p $out/bin $out/lib $out/share/burrito
    
            # Copy burrito_converter
            cp ${burrito_converter}/bin/burrito_converter $out/bin/
    
            # Copy burrito_link files
            mkdir -p $out/share/burrito_link
            cp ${burrito_link}/bin/burrito_link.exe $out/share/burrito_link/
            cp ${burrito_link}/bin/d3d11.dll $out/share/burrito_link/
            cp ${burrito_link}/bin/arcdps_burrito_link.dll $out/share/burrito_link/
    
            # Copy burrito UI
            cp ${burrito_ui}/bin/burrito.x86_64 $out/bin/
            chmod +w $out/bin/burrito.x86_64
    
            # Check for PCK file and copy if exists
            cp ${burrito_ui}/bin/burrito.pck $out/bin/burrito.pck
    
            # Copy libraries to the expected locations for GDNative
            mkdir -p $out/share/burrito/burrito-fg/target/release/
            cp ${burrito_fg}/lib/libburrito_fg.so $out/share/burrito/burrito-fg/target/release/
            chmod +w $out/share/burrito/burrito-fg/target/release/libburrito_fg.so
    
            mkdir -p $out/share/burrito/taco_parser/target/release/
            cp ${taco_parser}/lib/libgw2_taco_parser.so $out/share/burrito/taco_parser/target/release/
            chmod +w $out/share/burrito/taco_parser/target/release/libgw2_taco_parser.so
    
            # Also copy to lib directory for general access
            cp ${burrito_fg}/lib/libburrito_fg.so $out/lib/
            chmod +w $out/lib/libburrito_fg.so

            cp ${taco_parser}/lib/libgw2_taco_parser.so $out/lib/
            chmod +w $out/lib/libgw2_taco_parser.so

            # Create runtime dependencies string
            RUNTIME_DEPS="${lib.makeLibraryPath runtimeDeps}"

            # Patch the executable to set the correct interpreter and RPATH
            patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/bin/burrito.x86_64
            patchelf --set-rpath "$RUNTIME_DEPS:$out/lib" $out/bin/burrito.x86_64

            # Additionally patch the GDNative libraries
            patchelf --set-rpath "$RUNTIME_DEPS:$out/lib" $out/lib/libburrito_fg.so
            patchelf --set-rpath "$RUNTIME_DEPS:$out/lib" $out/lib/libgw2_taco_parser.so
    
            # Create a wrapper script with proper working directory
            makeWrapper $out/bin/burrito.x86_64 $out/bin/burrito \
              --chdir $out/bin
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
              glibc # ldd
              file
              strace

              # Original build dependencies
              unzip
              curl

              burrito
            ];

            shellHook = ''
              echo "Debugging environment for Godot headless"
              echo "To debug the Godot binary, run:"
              echo "ldd ${burrito}/bin/burrito"
              echo "file ${burrito}/bin/burrito"
              echo "strace ${burrito}/bin/burrito"
            '';
          };
        };
      }
    );
}

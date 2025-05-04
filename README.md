# Burrito GW2 Flake

This repository contains an attempt to create a Nix flake for [Burrito](https://github.com/AsherGlick/Burrito), a Guild Wars 2 overlay application.

## Current State

The flake currently provides a working implementation using the `buildFHSUserEnv` approach. This implementation:

- Successfully runs the Burrito application in a FHS-compatible environment
- Uses a wrapper script to ensure the application runs from the correct directory
- Handles the required dependencies and runtime environment

## Known Issues and Limitations

### Why We Can't Use `mkDerivation` on Release Files

We've attempted to use `mkDerivation` with the pre-built release files, but encountered several obstacles:

1. **Embedded PCK in Binary**: Burrito is built with Godot, which embeds the `.pck` file (containing project data) directly in the binary. Standard ELF patching methods like `patchelf` or `autoPatchelfHook` corrupt this embedded data, resulting in errors:
```
Error: Couldn't load project data at path ".". Is the .pck file missing?
```

2. **Dynamic Linking**: The pre-built binary requires specific dynamic linking to work on NixOS:
```
Could not start dynamically linked executable: ./burrito.x86_64
NixOS cannot run dynamically linked executables intended for generic
linux environments out of the box.
```

3. **Runtime Path Issues**: Burrito requires access to the `xml_converter` executable in the same directory during runtime. Managing this path relationship in a Nix store directory structure proves challenging.

## Future Work

Potential improvements to explore:

1. **Build from Source**: Creating a proper derivation by building Burrito from source code rather than using pre-built binaries. This would allow for proper integration with the Nix ecosystem.

2. **DLL Integration**: Adding configuration options for the GW2 Wine path to properly symlink the burrito-link DLL.

## Usage

To use the Burrito overlay:

```bash
# Run directly
nix run github:lumpsoid/burrito-gw2-flake#burrito-fhs

# Add to your flake inputs and use as a package
```

Note: The application requires a compatible Guild Wars 2 installation to function properly.


## Contributing

Running `nix develop` (or using direnv) allows to test `burrito-gw2` (built via FHS) and `burrito` (built via sources).



# Gameplay Shader Reconstruction Design

## Intent

Restore visible and recognizable gameplay rendering in the reconstructed Baldi's Basics Plus Unity project on Android. The project has 52 exported `.shader` files, all containing AssetRipper dummy shader bodies, and no original `.shadergraph` or `.shadersubgraph` files. The user asked to preserve shaders with usable source and recreate the others.

## Approaches

1. **Use AssetRipper shader decompilation for every shader.** This could recover some compiled behavior, but the available PC build contains DX11 shaders and AssetRipper documents this route as experimental; DX11 decompilation requires Windows. This environment has no local AssetRipper runtime or graph sources.
2. **Restore package-owned shaders from Unity URP/TMP packages, then recreate game-owned shaders in place.** The existing CI remapper already maps matching shader names to real package GUIDs. For game shaders, preserve filenames, shader names, GUIDs, serialized properties, and material references; rebuild the shader bodies as URP-compatible ShaderLab/HLSL using the available material data and C# global/property writes. **Chosen:** this is the only available approach that preserves project references and produces shaders the Android build can compile.
3. **Replace every shader with a generic URP Lit/Unlit shader.** This would be fast but would lose alpha clipping, poster composition, per-cell lightmaps, fog, glitch/dither behavior, and map/skybox effects that the scripts and material properties explicitly use.

## Goals

- Remove AssetRipper placeholder bodies from game-owned shaders.
- Keep Unity package shaders supplied by URP/TMP packages and remapped by name.
- Keep the existing shader GUIDs and material property names so serialized assets and runtime `MaterialPropertyBlock` writes continue to work.
- Provide URP-compatible forward rendering for OpenGLES3 and Vulkan on Unity 2021.3 / URP 12.1.
- Preserve cutout/depth-only behavior for masks and alpha-clipped tile/poster materials.

## Non-goals and limitations

- This is a reconstruction, not recovery of the original Shader Graph source. Exact visual parity cannot be claimed from serialized properties alone.
- Do not hand-recreate URP/TMP hidden package shaders when the package already owns that shader name.
- Do not use a graphics API switch as a substitute for correct shader code.

## Shader groups

- Package-owned hidden URP, Shader Graph fallback, terrain, and TMP names: keep references pointed to installed package sources through `tools/ci_package_remap.py`.
- Core game materials: `Shader Graphs/Standard`, `Whirlpool`, `TileStandard` variants, `MaskedStandard`, `Masked/Mask`, `SpriteStandard`, `SpriteStandard_NoBatching`, `MapTile`, `Skybox`, `Particle`, `PixelFilter`, and `Polygon`.
- Shared behavior to honor where the serialized property names show it: `_MainTex`, `_TextureOffset`, `_Tiling`, `_TextureColor`, `_ColorMultiplier`, `_ColorGuide`, `_LightMap`, `_LightGuide`, `_Offset`, poster inputs, `_PercentInvisible`, `_SpriteRotation`, `_Fog*`, `_ColorGlitch*`, `_SpriteColorGlitch*`, `_Skybox*`, and `_texelsPerPixel`.

## Validation

- Static audit: classify package-owned versus game-owned shader names; ensure no game-owned shader still contains `DummyShaderTextExporter` and every referenced property used by scripts is declared.
- CI: compile the complete APK through the reconstructed workflow for OpenGLES3 and Vulkan settings, inspect Unity shader compile errors and package remap counts.
- Device check: after the workflow finishes, compare the same gameplay entry on the target device and collect Unity logcat. Shader compilation alone does not prove the level camera presents geometry.

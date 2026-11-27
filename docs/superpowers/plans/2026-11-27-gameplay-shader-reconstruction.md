# Gameplay Shader Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace dummy game shaders with URP-compatible reconstructed ShaderLab while preserving package-owned URP/TMP shader implementations.

**Architecture:** Keep each game shader's existing path, shader name, GUID, and serialized properties. Let `ci_package_remap.py` direct package-owned names to Unity 2021.3 package sources and remove duplicate dummy declarations after references are redirected. Reconstruct each custom game shader in place with a URP-compatible forward pass.

**Tech Stack:** Unity 2021.3.45f1, URP 12.1.15, ShaderLab/HLSL, Mono Android APK, OpenGLES3/Vulkan.

**Spec:** `docs/superpowers/specs/2026-11-27-gameplay-shader-reconstruction-design.md`

## Global Constraints

- Keep original shader names, `.shader` paths, `.meta` GUIDs, and material property names.
- Use URP 12.1 APIs and passes; do not use Built-in Render Pipeline surface shaders.
- Support the serialized runtime globals and material property writes from `Assets/Scripts/Assembly-CSharp`.
- Rebuild the APK only through `build-reconstructed-unity-apk.yml`; do not run `build-apk.yml`.
- Treat visual parity as unverified until target-device comparison.

## Review Focus

- Alpha-clip tile/poster variants must discard transparent texels and still write depth; inspect their shader pass state and build log.
- `Shader Graphs/Standard` is used by about 250 materials; keep texture tiling, offsets, color, lightmap inputs, and custom globals declared.
- Sprite shaders receive per-renderer property blocks; preserve fog, dither, glitch, invisible-percent, and rotation properties and check all `Set*` script writes.
- The skybox shader uses global skybox texture/color and fog state; avoid rendering it as a regular opaque mesh.
- Package remapping must point package-owned shader GUIDs at package source; inspect the remap count and resulting build log.

---

### Task 1: Classify and restore package-owned shader references

**Files:**
- Inspect `tools/ci_package_remap.py` and Unity shader `.meta` files.
- Inspect `Assets/MonoBehaviour/UniversalRenderPipelineAsset_Renderer.asset` and `Assets/Resources/GraphicsSettings.asset`.

- [x] Inventory all 52 exported shader names; the 15 game-owned shader bodies have been reconstructed and package-owned shader references are supplied by URP/TMP package sources during CI.
- [x] Add narrowly scoped aliases for the two `Hidden/kMotion/*MotionVectors` exports, whose URP 12.1 package names use the `Hidden/Universal Render Pipeline/*MotionVectors` namespace.
- [ ] Record final package remap counts from the next build log.

### Task 2: Reconstruct world and tile shaders

**Files:**
- Modify `Assets/Shader/Shader Graphs_Standard.shader`.
- Modify `Assets/Shader/Shader Graphs_Whirlpool.shader`.
- Modify `Assets/Shader/Shader Graphs_TileStandard.shader`.
- Modify `Assets/Shader/Shader Graphs_TileStandard_AlphaClip.shader`.
- Modify `Assets/Shader/Shader Graphs_TileStandardWPoster.shader`.
- Modify `Assets/Shader/Shader Graphs_TileStandardWPoster_AlphaClip.shader`.
- Create `Assets/Shader/Includes/BBPlusWorld.hlsl`.

- [x] Implement URP forward vertex/fragment paths for world and tile materials using their textures, tiling/offset, color, light-map, and fog inputs.
- [x] Keep poster property-block texture inputs and alpha clipping in the alpha-clip tile variants.
- [x] Keep the Whirlpool material's standard property contract; its original graph/effect controls were not recoverable from the export.
- [x] Static audit confirms the game-owned shader bodies no longer contain dummy markers.

### Task 3: Reconstruct masks, map, sprite, and effect shaders

**Files:**
- Modify `Assets/Shader/Masked_Mask.shader`.
- Modify `Assets/Shader/Shader Graphs_MaskedStandard.shader`.
- Modify `Assets/Shader/Shader Graphs_MapTile.shader`.
- Modify `Assets/Shader/Shader Graphs_SpriteStandard.shader`.
- Modify `Assets/Shader/SpriteStandard_NoBatching.shader`.
- Modify `Assets/Shader/Shader Graphs_Skybox.shader`.
- Modify `Assets/Shader/Shader Graphs_Particle.shader`.
- Modify `Assets/Shader/Shader Graphs_PixelFilter.shader`.
- Modify `Assets/Shader/Shader Graphs_Polygon.shader`.
- Create `Assets/Shader/Includes/BBPlusEffects.hlsl`.

- [x] Implement a depth-only mask pass and a cutout-capable masked material pass, including sky rendering for `_RenderSky`.
- [x] Implement sprite tint, fog, invisibility dithering, rotation, and glitch property inputs.
- [x] Implement map, cubemap skybox, particle, pixel-filter, and polygon passes using their serialized inputs.
- [x] Static audit confirms the 15 game-owned shader bodies no longer contain dummy markers and their runtime-written material inputs are declared.

### Task 4: Verify APK shader compilation and rendering evidence

**Files:**
- Update the existing audit plan with build results; modify shader sources only if CI identifies compile failures.

- [ ] After the currently running workflow reports completion, update the project ZIP with shader changes and run only `build-reconstructed-unity-apk.yml` with `OpenGLES3`.
- [ ] Inspect Unity logs for shader compile/link errors, remapped shader counts, APK architecture, and Mono backend.
- [ ] If available, run an otherwise identical Vulkan build for A/B comparison; do not interpret GLES3 success alone as proof that graphics API caused the blue screen.
- [ ] On a connected target device, compare the elevator-to-level transition and capture `adb logcat -s Unity`; record whether the gameplay Base camera presents geometry after `BeginPlay`.


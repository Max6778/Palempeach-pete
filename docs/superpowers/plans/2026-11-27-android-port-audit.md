# Android Port Audit and Repair Plan

## Evidence collected

- Workflow run 24 compiled the project but failed Android packaging because no Android CPU architecture was enabled. The build script assigns ARM64, but the project setting was serialized as `0` and the failure log reports no target architecture.
- TMP's pre-build processor logged a `MissingReferenceException` for the `LiberationSans SDF - Fallback` atlas. Its atlas texture GUID is absent from the project; its material points to the same missing GUID.
- `LocalizationManager` and `Credits` call synchronous `System.IO.File` methods on `Application.streamingAssetsPath`. Unity documents this path as an APK URL on Android and requires `UnityWebRequest`; the old APK log also reported a missing localization file.
- The game uses a URP camera stack and its gameplay camera clears to slate blue. The blue gameplay screen is consistent with a clear-only camera, but static source inspection does not yet identify a proven camera-stack or shader defect.
- All 52 exported shader files were checked; gameplay Shader Graph exports contain AssetRipper's `DummyShaderTextExporter` placeholder passes. AssetRipper documents Dummy mode as preserving properties and fallbacks while replacing shader logic with generic opaque code. This is a confirmed visual fidelity defect, though it does not alone prove the cause of the blue screen.
- The generator disables gameplay camera culling while building. `LevelGenerator` can `yield break` for dimensions above 256 after setting `levelInProgress`, without restoring cameras or completing; `GameInitializer.WaitForGenerator` then waits indefinitely. The watchdog also sets an error flag but leaves the wait active. This is a concrete blue-screen failure path.

## Work

1. Make the Android architecture explicit in project settings and build options; assert the setting before building so CI stops with a precise setup error.
2. Repair the TMP fallback font's missing atlas references using the checked-in Liberation Sans SDF atlas.
3. Make localization and credits data load from imported `Resources` TextAssets so startup is synchronous and works on Android APKs; initialize localization through the singleton's Awake hook.
4. Make generation failure paths release camera/audio state and stop the initializer from waiting forever; add a selectable GLES3/Vulkan setting for controlled A/B runs.
5. Continue static checks of Android input, scene/camera setup, shaders, and serialized references; record the dummy-shader limitation and determine whether original shader data or another export path is available locally.
6. Repack the Unity project, run the authorized reconstructed Mono Android workflow, inspect the resulting APK/log, and report remaining device validation limits.

## Validation

- Verify all TMP atlas GUIDs resolve and project/build settings specify ARM64.
- Verify all runtime `StreamingAssets` consumers are removed or use Android-compatible access.
- Run the reconstructed workflow only (not `build-apk.yml`), inspect its Unity log and APK architecture/backend, and install/run only if a device is connected.

import subprocess
import tempfile
import json
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "ci_package_remap.py"


class PackageRemapTests(unittest.TestCase):
    def run_helper(self, *args):
        return subprocess.run(
            ["python3", str(SCRIPT), *map(str, args)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout

    def test_prepare_removes_package_dlls_but_keeps_game_plugins(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp) / "UnityProject"
            plugins = project / "Assets" / "Plugins"
            plugins.mkdir(parents=True)
            (plugins / "Unity.RenderPipelines.Universal.Runtime.dll").write_bytes(b"stub")
            (plugins / "Rewired_Core.dll").write_bytes(b"game plugin")

            self.run_helper("prepare", project)

            self.assertFalse((plugins / "Unity.RenderPipelines.Universal.Runtime.dll").exists())
            self.assertTrue((plugins / "Rewired_Core.dll").exists())

    def test_prepare_adds_urp_package_and_removes_windows_only_rewired_import(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp) / "UnityProject"
            manifest = project / "Packages" / "manifest.json"
            manifest.parent.mkdir(parents=True)
            manifest.write_text('{"dependencies": {"com.unity.textmeshpro": "3.0.6"}}')
            rewired = project / "Assets/Scripts/Assembly-CSharp/Rewired/Utils/ExternalTools.cs"
            rewired.parent.mkdir(parents=True)
            rewired.write_text(
                "using Rewired.Utils.Platforms.Windows;\n"
                "class ExternalTools {}\n"
            )

            self.run_helper("prepare", project)

            dependencies = json.loads(manifest.read_text())["dependencies"]
            self.assertEqual(dependencies["com.unity.render-pipelines.universal"], "12.1.15")
            self.assertEqual(dependencies["com.unity.ugui"], "1.0.0")
            contents = rewired.read_text()
            self.assertNotIn("Rewired.Utils.Platforms.Windows", contents)
            self.assertIn("Rewired.Utils.Platforms.Android", contents)

    def test_remap_repoints_package_script_and_shader_guids(self):
        old_script_guid = "11111111111111111111111111111111"
        new_script_guid = "22222222222222222222222222222222"
        old_shader_guid = "33333333333333333333333333333333"
        new_shader_guid = "44444444444444444444444444444444"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            project = root / "UnityProject"
            recovered = project / "RecoveredSourceArchive" / "Unity.RenderPipelines.Universal.Runtime"
            package = project / "Library" / "PackageCache" / "com.unity.render-pipelines.universal@12.1.0"
            assets = project / "Assets"
            for path in (recovered / "UnityEngine/Rendering/Universal", package / "Runtime/Universal", assets / "Scene"):
                path.mkdir(parents=True)

            (recovered / "UnityEngine/Rendering/Universal/FakeCameraData.cs").write_text(
                "namespace UnityEngine.Rendering.Universal { public class FakeCameraData {} }"
            )
            (recovered / "UnityEngine/Rendering/Universal/FakeCameraData.cs.meta").write_text(
                f"fileFormatVersion: 2\nguid: {old_script_guid}\n"
            )
            (package / "Runtime/Universal/FakeCameraData.cs").write_text(
                "namespace UnityEngine.Rendering.Universal { public class FakeCameraData {} }"
            )
            (package / "Runtime/Universal/FakeCameraData.cs.meta").write_text(
                f"fileFormatVersion: 2\nguid: {new_script_guid}\n"
            )
            (assets / "Shader/placeholder.shader").parent.mkdir(parents=True)
            (assets / "Shader/placeholder.shader").write_text('Shader "Universal Render Pipeline/Fake" { SubShader {} }')
            (assets / "Shader/placeholder.shader.meta").write_text(f"fileFormatVersion: 2\nguid: {old_shader_guid}\n")
            package_shader = package / "Shaders/Fake.shader"
            package_shader.parent.mkdir(parents=True)
            package_shader.write_text('Shader "Universal Render Pipeline/Fake" { SubShader {} }')
            package_shader.with_suffix(".shader.meta").write_text(f"fileFormatVersion: 2\nguid: {new_shader_guid}\n")
            scene = assets / "Scene/Test.unity"
            scene.write_text(
                f"m_Script: {{fileID: 11500000, guid: {old_script_guid}, type: 3}}\n"
                f"m_Shader: {{fileID: 4800000, guid: {old_shader_guid}, type: 3}}\n"
            )

            self.run_helper("remap", project, project / "Library/PackageCache", root / "BuiltinPackages")

            remapped = scene.read_text()
            self.assertIn(new_script_guid, remapped)
            self.assertIn(new_shader_guid, remapped)
            self.assertNotIn(old_script_guid, remapped)
            self.assertNotIn(old_shader_guid, remapped)


if __name__ == "__main__":
    unittest.main()

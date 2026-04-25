from __future__ import annotations
import subprocess
import tempfile
import textwrap
from pathlib import Path
from ..config import settings

# Four-angle azimuths (degrees) used for multi-view CLIP embedding
_AZIMUTHS = [0, 90, 180, 270]


def render_usdz_4angles(usdz_path: str | Path) -> list[Path]:
    """Render a USDZ file from four azimuths using Blender headless.

    Returns a list of four PNG paths inside a temp directory.
    Caller is responsible for cleanup.
    """
    usdz_path = Path(usdz_path)
    tmpdir = Path(tempfile.mkdtemp(prefix="render_"))
    output_paths: list[Path] = []

    for az in _AZIMUTHS:
        out_path = tmpdir / f"render_{az:03d}.png"
        script = textwrap.dedent(f"""
            import bpy, math
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.wm.usd_import(filepath=r"{usdz_path}")
            bpy.ops.object.select_all(action='SELECT')
            bpy.ops.view3d.camera_to_view_selected()
            cam = bpy.context.scene.camera
            if cam is None:
                bpy.ops.object.camera_add()
                cam = bpy.context.active_object
                bpy.context.scene.camera = cam
            cam.rotation_euler[2] = math.radians({az})
            bpy.context.scene.render.filepath = r"{out_path}"
            bpy.context.scene.render.image_settings.file_format = 'PNG'
            bpy.context.scene.render.resolution_x = 512
            bpy.context.scene.render.resolution_y = 512
            bpy.ops.render.render(write_still=True)
        """)
        script_path = tmpdir / f"render_{az:03d}.py"
        script_path.write_text(script)
        subprocess.run(
            [settings.blender_path, "--background", "--python", str(script_path)],
            check=True,
            capture_output=True,
        )
        output_paths.append(out_path)

    return output_paths

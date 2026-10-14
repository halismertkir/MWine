from pathlib import Path
import importlib.util
import tempfile

spec = importlib.util.spec_from_file_location("restore_saves", Path(__file__).parents[1] / "scripts/restore-saves.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as folder:
    project = Path(folder)
    prefix = project / "new-prefix"
    relative = "bottles/steam/drive_c/users/mert/AppData/Roaming/Godot/app_userdata/Haystack Incremental"
    source = project / "preserved-data/2026-10-11" / relative
    (source / "saves").mkdir(parents=True)
    (source / "saves/slot.json").write_text("preserved")
    (source / "settings.cfg").write_text("original settings")
    (source / "shader_cache").mkdir()
    (source / "shader_cache/shader.bin").write_text("not a save")
    assert module.restore(project, "5165210", prefix) == 2
    destination = prefix / "drive_c/users/steamuser/AppData/Roaming/Godot/app_userdata/Haystack Incremental"
    assert not (destination / "shader_cache").exists()
    (destination / "saves/slot.json").write_text("new progress")
    assert module.restore(project, "5165210", prefix) == 0
    assert (destination / "saves/slot.json").read_text() == "new progress"
    assert module.restore(project, "3405340", prefix) == 0
print("Save restoration, cache exclusion and no-overwrite checks passed.")

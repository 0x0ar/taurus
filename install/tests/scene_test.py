#!/usr/bin/env python3
"""Tests for taurus scenes (src/scripts/scene.py), run in a sandbox: never touches the real settings."""
import json
import os
import subprocess
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(REPO, "src")
sys.path.insert(0, os.path.join(SRC, "scripts"))


class SceneTestBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", self.tmp]))
        env = {
            "TAURUS_DIR": SRC,
            "QS_SETTINGS": os.path.join(self.tmp, "settings.json"),
            "QS_STATE_DIR": os.path.join(self.tmp, "state"),
            "XDG_CONFIG_HOME": os.path.join(self.tmp, "config"),
            "HOME": self.tmp,
        }
        self._old = {k: os.environ.get(k) for k in env}
        os.environ.update(env)
        self.addCleanup(self._restore_env)
        import importlib
        import scene
        self.scene = importlib.reload(scene)
        # a stand-in for taurus-gamma with the same observable behaviour as the real 0.7.0 daemon:
        # `set` fixes a temperature and turns the schedule off, `auto on` turns it back on
        self.gamma_file = os.path.join(self.tmp, "gamma.json")
        self.set_gamma(auto=True, temperature=4200, day=6500, night=3500)
        impl = os.path.join(self.tmp, "gamma_impl.py")
        with open(impl, "w") as f:
            f.write("import json, sys\np = %r\nd = json.load(open(p))\n"
                    "if sys.argv[1] == 'set':\n    d.update(auto=False, temperature=int(sys.argv[2]), running=True)\n"
                    "json.dump(d, open(p, 'w'))\n" % self.gamma_file)
        stub = os.path.join(self.tmp, "gamma.sh")           # run as `bash gamma.sh set N`, like the real script
        with open(stub, "w") as f:
            f.write('#!/bin/bash\nexec python3 -I %s "$@"\n' % impl)
        os.chmod(stub, 0o755)
        self.scene.gamma_script = lambda: stub
        self.scene.gamma_available = lambda: True
        
        def fake_status():
            d = json.load(open(self.gamma_file))
            return d if d.get("running", True) else None

        def fake_run(*args):
            if args[:2] == ("auto", "on"):
                d = json.load(open(self.gamma_file))
                d.update(auto=True, day=int(args[args.index("--day") + 1]), night=int(args[args.index("--night") + 1]))
                d["temperature"] = d["night"]
                json.dump(d, open(self.gamma_file, "w"))
            return True

        self.scene.gamma_status = fake_status
        self.scene.gamma_run = fake_run
        # theme changes go through the CLI (IPC to a running shell): record them instead
        self.theme_calls = []

        def fake_taurus(*args):
            self.theme_calls.append(args)
            data = self.scene.read_json(self.scene.settings_path(), {})
            theme = data.setdefault("theme", {})
            if args[:3] == ("set", "theme", "preset"):
                theme.update(activePreset=args[3], matugen=False)
            elif args[:3] == ("set", "theme", "matugen"):
                theme.update(matugen=(args[3] == "on"))
            self.scene.write_json(self.scene.settings_path(), data)
            return subprocess.CompletedProcess(args, 0, "", "")

        self.scene.run_taurus = fake_taurus
        self.write_settings({"notifications": {"dnd": False}, "dock": {"autohide": False},
                             "bar": {"autohide": False}, "general": {"muteSfx": False},
                             "idle": {"manualInhibit": False}, "theme": {"activePreset": "Taurus", "matugen": False},
                             "scenes": {"auto": False}})

    def _restore_env(self):
        for k, v in self._old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def write_settings(self, data):
        self.scene.write_json(self.scene.settings_path(), data)

    def set_gamma(self, **d):
        d.setdefault("day", 6500); d.setdefault("night", 4000)
        json.dump(d, open(self.gamma_file, "w"))

    def gamma(self):
        return json.load(open(self.gamma_file))

    def settings(self):
        return self.scene.read_json(self.scene.settings_path(), {})

    def put_scene(self, name, obj):
        d = self.scene.user_dir()
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, name + ".json"), "w") as f:
            json.dump(obj, f)


class ValidationTests(SceneTestBase):
    def test_bundled_scenes_are_valid(self):
        names = [n for n in self.scene.scene_files()]
        self.assertTrue({"work", "gaming", "night"} <= set(names))
        for n in names:
            _, _, errors = self.scene.load_scene(n)
            self.assertEqual(errors, [], n)

    def test_unknown_field_is_rejected(self):
        _, errors = self.scene.validate_scene({"name": "x", "dnd": True, "run": "rm -rf /"})
        self.assertTrue(any("unknown field" in e for e in errors))

    def test_no_command_strings_exist_in_the_schema(self):
        self.assertFalse({"commands", "command", "exec", "run"} & set(self.scene.FIELDS))

    def test_type_and_range_checks(self):
        bad = [{"name": "x", "dnd": "yes"}, {"name": "x", "gamma_temperature": 50},
               {"name": "x", "gamma_temperature": True}, {"name": "x", "theme": "../../etc/passwd"},
               {"name": "x", "dnd": True, "triggers": {"time": {"from": "25:00", "to": "07:00"}}},
               {"name": "x", "dnd": True, "triggers": {"apps": ["a b"]}},
               {"name": "../evil", "dnd": True}, {"name": "x"}]
        for obj in bad:
            clean, errors = self.scene.validate_scene(obj)
            self.assertIsNone(clean, obj)
            self.assertTrue(errors, obj)


class TriggerTests(SceneTestBase):
    def test_time_window_crosses_midnight(self):
        w = {"from": "22:00", "to": "07:00"}
        self.assertTrue(self.scene.time_in(w, 23 * 60 + 30))
        self.assertTrue(self.scene.time_in(w, 3 * 60))
        self.assertFalse(self.scene.time_in(w, 12 * 60))
        self.assertFalse(self.scene.time_in({"from": "08:00", "to": "08:00"}, 8 * 60))

    def test_app_beats_time_and_ignored_classes_decide_nothing(self):
        night = 23 * 60
        self.assertEqual(self.scene.match("steam_app_123", night), "gaming")
        self.assertEqual(self.scene.match("firefox", night), "night")
        self.assertIsNone(self.scene.match("firefox", 12 * 60))
        self.assertEqual(self.scene.match("Desktop", night), "night")


class ApplyTests(SceneTestBase):
    def test_apply_and_off_round_trip(self):
        before = self.settings()
        self.assertEqual(self.scene.cmd_apply("gaming"), 0)
        s = self.settings()
        self.assertTrue(s["notifications"]["dnd"] and s["dock"]["autohide"] and s["idle"]["manualInhibit"])
        self.assertEqual((self.gamma()["auto"], self.gamma()["temperature"]), (False, 6500))
        self.assertEqual(self.scene.load_state()["active"], "gaming")
        self.scene.cmd_off()
        after = self.settings()
        after["idle"].pop("caffeineStartTime", None)   # turning caffeine off zeroes its timer, like the CLI
        after["idle"].pop("caffeineEndTime", None)
        self.assertEqual(after, before)
        self.assertTrue(self.gamma()["auto"])      # the day/night schedule is back on
        self.assertEqual(self.scene.load_state(), {})

    def test_values_changed_while_active_are_kept(self):
        self.scene.cmd_apply("gaming")
        s = self.settings()
        s["notifications"]["dnd"] = False          # the user turns DND off by hand
        self.write_settings(s)
        self.scene.cmd_off()
        s = self.settings()
        self.assertFalse(s["notifications"]["dnd"])           # kept
        self.assertFalse(s["dock"]["autohide"])               # restored

    def test_switching_does_not_leak_fields(self):
        self.scene.cmd_apply("gaming")
        self.scene.cmd_apply("work")                   # work sets only dnd and mute_sfx
        s = self.settings()
        self.assertFalse(s["dock"]["autohide"])
        self.assertFalse(s["idle"]["manualInhibit"])
        self.assertTrue(s["notifications"]["dnd"])

    def test_a_manual_gamma_temperature_is_restored_as_it_was(self):
        self.set_gamma(auto=False, temperature=5000)    # the user had set 5000 K by hand
        self.scene.cmd_apply("gaming")
        self.assertEqual(self.gamma()["temperature"], 6500)
        self.scene.cmd_off()
        self.assertEqual((self.gamma()["auto"], self.gamma()["temperature"]), (False, 5000))

    def test_the_schedule_comes_back_with_its_own_day_and_night_temperatures(self):
        self.set_gamma(auto=True, temperature=3000, day=7000, night=3000)
        self.scene.cmd_apply("night")
        self.assertFalse(self.gamma()["auto"])
        self.scene.cmd_off()
        g = self.gamma()
        self.assertEqual((g["auto"], g["day"], g["night"]), (True, 7000, 3000))

    def test_a_filter_that_was_not_running_starts_neutral_and_ends_neutral(self):
        self.set_gamma(auto=False, temperature=6500, running=False)
        self.scene.cmd_apply("night")
        self.assertEqual(self.gamma()["temperature"], 3800)
        self.scene.cmd_off()
        self.assertEqual(self.gamma()["temperature"], 6500)

    def test_a_change_made_while_the_scene_is_active_is_kept(self):
        self.scene.cmd_apply("night")
        self.set_gamma(auto=False, temperature=2500)    # the user changes the warmth meanwhile
        self.scene.cmd_off()
        self.assertEqual(self.gamma()["temperature"], 2500)

    def test_theme_field_goes_through_the_cli_and_is_restored(self):
        self.put_scene("blue", {"name": "blue", "theme": "Nord"})
        self.scene.cmd_apply("blue")
        self.assertEqual(self.settings()["theme"]["activePreset"], "Nord")
        self.scene.cmd_off()
        self.assertEqual(self.settings()["theme"]["activePreset"], "Taurus")
        self.assertEqual([c[:3] for c in self.theme_calls], [("set", "theme", "preset")] * 2)

    def test_scene_writes_do_not_create_settings_backups(self):
        backups = os.path.join(self.tmp, "state", "backups")
        self.scene.cmd_apply("gaming")
        self.scene.cmd_off()
        self.assertFalse(os.path.isdir(backups) and os.listdir(backups))

    def test_unknown_scene_fails_cleanly(self):
        self.assertEqual(self.scene.cmd_apply("nope"), 1)
        self.assertEqual(self.settings()["notifications"]["dnd"], False)


class TickTests(SceneTestBase):
    def tick(self, app, hour=12):
        t = 1700000000
        lt = __import__("time").localtime(t)
        now = t - (lt.tm_hour * 3600 + lt.tm_min * 60 + lt.tm_sec) + hour * 3600
        return self.scene.cmd_tick(app, now)

    def enable(self):
        s = self.settings(); s["scenes"]["auto"] = True; self.write_settings(s)

    def test_auto_off_changes_nothing(self):
        self.tick("steam_app_1")
        self.assertEqual(self.scene.load_state(), {})

    def test_focus_a_game_then_leave(self):
        self.enable()
        self.tick("steam_app_1")
        self.assertEqual(self.scene.load_state()["active"], "gaming")
        self.tick("steam_app_1")                      # same app again: nothing to do
        self.tick("Quickshell")                       # the launcher opened: scene stays
        self.assertEqual(self.scene.load_state()["active"], "gaming")
        self.tick("firefox")
        self.assertEqual(self.scene.load_state(), {})
        self.assertFalse(self.settings()["notifications"]["dnd"])

    def test_time_scene_and_priority(self):
        self.enable()
        self.tick("firefox", hour=23)
        self.assertEqual(self.scene.load_state()["active"], "night")
        self.tick("steam_app_9", hour=23)
        self.assertEqual(self.scene.load_state()["active"], "gaming")
        self.tick("firefox", hour=12)
        self.assertEqual(self.scene.load_state(), {})

    def test_a_manual_scene_is_never_overridden(self):
        self.enable()
        self.scene.cmd_apply("work", "manual")
        self.tick("steam_app_1")
        self.assertEqual(self.scene.load_state()["active"], "work")


class FilesTests(SceneTestBase):
    def test_save_from_current_then_delete(self):
        s = self.settings(); s["notifications"]["dnd"] = True; self.write_settings(s)
        self.assertEqual(self.scene.cmd_save("mine", ["dnd", "mute_sfx"]), 0)
        scene, source, errors = self.scene.load_scene("mine")
        self.assertEqual((errors, source, scene["dnd"]), ([], "user", True))
        self.assertEqual(self.scene.cmd_delete("mine"), 0)
        self.assertEqual(self.scene.cmd_delete("gaming"), 1)     # bundled scenes are read-only

    def test_user_scene_overrides_a_bundled_one(self):
        self.put_scene("work", {"name": "work", "dnd": False})
        scene, source, _ = self.scene.load_scene("work")
        self.assertEqual((source, scene["dnd"]), ("user", False))

    def test_invalid_user_scene_is_listed_but_never_applied(self):
        self.put_scene("bad", {"name": "bad", "dnd": "maybe"})
        self.assertEqual(self.scene.cmd_apply("bad"), 1)
        self.assertEqual(self.scene.load_state(), {})


if __name__ == "__main__":
    unittest.main(verbosity=1)

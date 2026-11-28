#!/usr/bin/env python3
"""Tests for `taurus share` (src/scripts/share.py): nothing personal leaves, nothing hostile gets in."""
import copy
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(REPO, "src")
DEFAULTS = json.load(open(os.path.join(REPO, "config", "taurus", "settings.json")))
THEME = json.load(open(os.path.join(SRC, "assets", "themes", "Taurus.json")))


class ShareBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", self.tmp]))
        env = {"TAURUS_DIR": SRC, "QS_SETTINGS": os.path.join(self.tmp, "settings.json"),
               "QS_STATE_DIR": os.path.join(self.tmp, "state"), "XDG_CONFIG_HOME": os.path.join(self.tmp, "config"),
               "HOME": self.tmp}
        self._old = {k: os.environ.get(k) for k in env}
        os.environ.update(env)
        self.addCleanup(self._restore)
        spec = importlib.util.spec_from_file_location("share", os.path.join(SRC, "scripts", "share.py"))
        self.share = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.share)
        self.backups = 0

        def fake_backup():
            self.backups += 1
            return True

        self.share.backup_settings = fake_backup
        self.taurus_calls = []
        self.share.run_taurus = lambda *a: self.taurus_calls.append(a) or True
        self.write_settings(copy.deepcopy(DEFAULTS))

    def _restore(self):
        for k, v in self._old.items():
            os.environ.pop(k, None) if v is None else os.environ.__setitem__(k, v)

    def write_settings(self, d):
        json.dump(d, open(self.share.settings_path(), "w"))

    def settings(self):
        return json.load(open(self.share.settings_path()))

    def export(self):
        out = os.path.join(self.tmp, "bundle.json")
        with redirect_stderr(io.StringIO()):
            self.share.cmd_export(["-o", out])
        return json.load(open(out))

    def write_bundle(self, **parts):
        path = os.path.join(self.tmp, "in.json")
        json.dump(dict({"format": "taurus-setup", "version": 1}, **parts), open(path, "w"))
        return path

    def run_import(self, path, *flags):
        out = io.StringIO()
        with redirect_stdout(out), redirect_stderr(io.StringIO()):
            rc = self.share.cmd_import([path, *flags])
        return rc, out.getvalue()


class ExportTests(ShareBase):
    def test_only_what_differs_from_the_defaults(self):
        s = copy.deepcopy(DEFAULTS); s["bar"]["height"] = 61; self.write_settings(s)
        b = self.export()
        self.assertEqual(b["settings"], {"bar": {"height": 61}})

    def test_nothing_personal_or_machine_specific_is_exported(self):
        s = copy.deepcopy(DEFAULTS)
        s["general"]["avatarPath"] = "/home/me/me.png"
        s["general"]["githubToken"] = "ghp_SECRET"
        s["general"]["location"] = {"lat": 12.3, "lon": 45.6}
        s["display"]["monitors"] = {"DP-1": {"x": 0}}
        s["dock"]["apps"] = ["firefox"]
        s["notifications"]["soundFile"] = "/home/me/ding.wav"
        s["notifications"]["dnd"] = True
        s["syspanel"]["clipState"] = 9
        s["general"]["note"] = "/home/me/private"          # innocent key, personal value
        s["bar"]["opacity"] = 80                             # "city" in "opacity" must not trigger
        self.write_settings(s)
        b = self.export()
        text = json.dumps(b["settings"])
        for secret in ("ghp_SECRET", "/home/me", "12.3", "firefox", "DP-1", "clipState"):
            self.assertNotIn(secret, text)
        self.assertEqual(b["settings"]["bar"]["opacity"], 80)
        reasons = {e["what"] for e in b["excluded"]}
        self.assertIn("settings.general.githubToken", reasons)
        self.assertIn("settings.general.avatarPath", reasons)

    def test_widget_text_and_images_are_stripped_from_layouts(self):
        d = os.path.join(self.share.widgets_dir(), "DP-1"); os.makedirs(d)
        json.dump([{"type": "notes", "wType": "notes", "wX": 10, "wY": 20, "wWidth": 300, "wHeight": 200,
                    "wImagePath": "/home/me/photo.png", "imagePath": "/home/me/photo.png",
                    "noteText": "my bank pin is 1234", "github": "someone", "size": 150, "showSeconds": True,
                    "wId": "w_1"}], open(os.path.join(d, "layout.json"), "w"))
        b = self.export()
        text = json.dumps(b["layouts"])
        for secret in ("bank pin", "someone", "photo.png"):
            self.assertNotIn(secret, text)
        w = b["layouts"]["DP-1"][0]
        self.assertEqual((w["wX"], w["wWidth"], w["size"], w["showSeconds"]), (10, 300, 150, True))
        self.assertNotIn("wId", w)

    def test_invalid_user_scenes_and_themes_are_left_out_not_exported(self):
        os.makedirs(self.share.themes_dir())
        json.dump({"name": "Bad", "colors": {"base": "red"}}, open(os.path.join(self.share.themes_dir(), "Bad.json"), "w"))
        sd = self.share.scene_mod.user_dir(); os.makedirs(sd)
        json.dump({"name": "evil", "dnd": True, "commands": ["rm -rf /"]}, open(os.path.join(sd, "evil.json"), "w"))
        b = self.export()
        self.assertEqual((b["themes"], b["scenes"]), ({}, {}))
        self.assertEqual(len(b["excluded"]), 2)


class ImportSafetyTests(ShareBase):
    def test_preview_writes_nothing(self):
        path = self.write_bundle(settings={"bar": {"height": 77}}, themes={"X": dict(THEME, name="X")})
        before = open(self.share.settings_path()).read()
        rc, out = self.run_import(path)
        self.assertEqual(rc, 0)
        self.assertIn("preview", out)
        self.assertEqual(open(self.share.settings_path()).read(), before)
        self.assertFalse(os.path.exists(self.share.themes_dir()))
        self.assertEqual(self.backups, 0)

    def test_apply_backs_up_first_then_merges(self):
        path = self.write_bundle(settings={"bar": {"height": 77}})
        self.assertEqual(self.run_import(path, "--apply")[0], 0)
        self.assertEqual(self.backups, 1)
        self.assertEqual(self.settings()["bar"]["height"], 77)
        self.assertEqual(self.settings()["dock"], DEFAULTS["dock"])            # the rest is untouched

    def test_unknown_keys_wrong_types_and_denied_keys_are_dropped_not_fatal(self):
        path = self.write_bundle(settings={"bar": {"height": "tall", "nonsense": 1, "width": 99},
                                           "general": {"avatarPath": "/x"}, "evil": {"a": 1},
                                           "dock": {"apps": ["x"]}, "scenes": {"auto": True}})
        rc, out = self.run_import(path, "--apply")
        self.assertEqual(rc, 0)
        s = self.settings()
        self.assertEqual(s["bar"]["width"], 99)                              # the good one went in
        self.assertEqual(s["bar"]["height"], DEFAULTS["bar"]["height"])
        self.assertNotIn("nonsense", s["bar"]); self.assertNotIn("evil", s)
        self.assertNotEqual(s["general"]["avatarPath"], "/x")
        self.assertFalse(s["scenes"]["auto"])                                # nobody can switch automation on for you
        self.assertIn("Ignored", out)

    def test_values_that_are_too_big_or_hold_paths_are_dropped(self):
        path = self.write_bundle(settings={"general": {"language": "x" * 500}, "theme": {"fontFamily": "/etc/passwd"}})
        self.run_import(path, "--apply")
        s = self.settings()
        self.assertEqual(s["general"]["language"], DEFAULTS["general"]["language"])
        self.assertEqual(s["theme"]["fontFamily"], DEFAULTS["theme"]["fontFamily"])

    def test_rejects_other_formats_versions_and_huge_files(self):
        for content in ('{"format": "other", "version": 1}', '{"format": "taurus-setup", "version": 2}', "not json", "[]"):
            p = os.path.join(self.tmp, "x.json"); open(p, "w").write(content)
            self.assertEqual(self.run_import(p, "--apply")[0], 1, content)
        big = os.path.join(self.tmp, "big.json")
        open(big, "w").write(json.dumps({"format": "taurus-setup", "version": 1, "pad": "x" * (1024 * 1024 + 1)}))
        self.assertEqual(self.run_import(big, "--apply")[0], 1)
        self.assertEqual(self.backups, 0)

    def test_themes_are_validated_and_names_cannot_escape_the_folder(self):
        good = dict(THEME, name="Shared One")
        path = self.write_bundle(themes={"a": good, "../../../tmp/pwn": dict(THEME, name="../../../tmp/pwn"),
                                         "b": {"name": "Bad", "colors": dict(THEME["colors"], base="url(x)")},
                                         "c": {"name": "Short", "colors": {"base": "#000000"}}})
        self.run_import(path, "--apply")
        self.assertEqual(os.listdir(self.share.themes_dir()), ["Shared One.json"])
        self.assertFalse(os.path.exists("/tmp/pwn.json"))
        saved = json.load(open(os.path.join(self.share.themes_dir(), "Shared One.json")))
        self.assertTrue(saved["isCustom"] and saved["category"] == "user")

    def test_a_theme_never_shadows_a_bundled_one_or_overwrites_yours_silently(self):
        path = self.write_bundle(themes={"t": dict(THEME, name="Taurus", colors=dict(THEME["colors"], base="#111111"))})
        self.run_import(path, "--apply")
        self.assertEqual(os.listdir(self.share.themes_dir()), ["Taurus-shared.json"])
        self.run_import(path, "--apply")                                     # second time: it exists now
        self.assertEqual(json.load(open(os.path.join(self.share.themes_dir(), "Taurus-shared.json")))["colors"]["base"], "#111111")
        mine = dict(THEME, name="Taurus-shared", colors=dict(THEME["colors"], base="#222222"))
        self.run_import(self.write_bundle(themes={"t": mine}), "--apply")
        self.assertEqual(json.load(open(os.path.join(self.share.themes_dir(), "Taurus-shared.json")))["colors"]["base"], "#111111")
        self.run_import(self.write_bundle(themes={"t": mine}), "--apply", "--overwrite")
        self.assertEqual(json.load(open(os.path.join(self.share.themes_dir(), "Taurus-shared.json")))["colors"]["base"], "#222222")

    def test_the_theme_switch_goes_through_the_cli_not_raw_settings(self):
        path = self.write_bundle(settings={"theme": {"activePreset": "Mine", "matugen": False, "borderRadius": 14}},
                                 themes={"Mine": dict(THEME, name="Mine")})
        self.run_import(path, "--apply")
        s = self.settings()
        self.assertEqual(s["theme"]["borderRadius"], 14)                       # a plain option still goes in
        self.assertEqual(s["theme"]["activePreset"], DEFAULTS["theme"]["activePreset"])   # not written raw
        self.assertEqual(self.taurus_calls, [("set", "theme", "preset", "Mine")])

    def test_a_renamed_theme_is_the_one_that_gets_selected(self):
        path = self.write_bundle(settings={"theme": {"activePreset": "Taurus"}},
                                 themes={"t": dict(THEME, name="Taurus", colors=dict(THEME["colors"], base="#111111"))})
        self.run_import(path, "--apply")
        self.assertEqual(self.taurus_calls, [("set", "theme", "preset", "Taurus-shared")])

    def test_matugen_and_unavailable_presets(self):
        self.run_import(self.write_bundle(settings={"theme": {"matugen": True}}), "--apply")
        self.assertEqual(self.taurus_calls, [("set", "theme", "matugen", "on")])
        self.taurus_calls.clear()
        rc, out = self.run_import(self.write_bundle(settings={"theme": {"activePreset": "Nope"}}), "--apply")
        self.assertEqual(self.taurus_calls, [])
        self.assertIn("not available here", out)

    def test_the_preview_does_not_switch_the_theme(self):
        self.run_import(self.write_bundle(settings={"theme": {"activePreset": "Nord"}}))
        self.assertEqual(self.taurus_calls, [])

    def test_scenes_with_commands_or_unknown_fields_are_refused(self):
        path = self.write_bundle(scenes={"ok": {"name": "calm", "dnd": True},
                                         "evil": {"name": "evil", "dnd": True, "commands": ["rm -rf ~"]},
                                         "evil2": {"name": "../x", "dnd": True},
                                         "evil3": {"name": "bad", "gamma_temperature": 99999}})
        rc, out = self.run_import(path, "--apply")
        self.assertEqual(sorted(os.listdir(self.share.scene_mod.user_dir())), ["calm.json"])
        self.assertIn("unknown field 'commands'", out)

    def test_a_scene_never_shadows_a_bundled_one(self):
        path = self.write_bundle(scenes={"g": {"name": "gaming", "dnd": False}})
        self.run_import(path, "--apply")
        self.assertEqual(os.listdir(self.share.scene_mod.user_dir()), ["gaming-shared.json"])

    def test_layouts_are_opt_in_known_monitors_only_and_keep_a_backup(self):
        d = os.path.join(self.share.widgets_dir(), "DP-1"); os.makedirs(d)
        json.dump([{"type": "clock", "wX": 1}], open(os.path.join(d, "layout.json"), "w"))
        incoming = {"DP-1": [{"type": "notes", "wX": 5, "noteText": "x"}], "HDMI-9": [{"type": "x"}], "../evil": []}
        path = self.write_bundle(layouts=incoming)
        self.run_import(path, "--apply")                                      # no --layouts
        self.assertEqual(json.load(open(os.path.join(d, "layout.json")))[0]["type"], "clock")
        self.run_import(path, "--apply", "--layouts")
        new = json.load(open(os.path.join(d, "layout.json")))
        self.assertEqual((new[0]["type"], new[0]["wX"], "noteText" in new[0]), ("notes", 5, False))
        self.assertTrue(os.path.exists(os.path.join(d, "layout.json.bak")))
        self.assertFalse(os.path.exists(os.path.join(self.share.widgets_dir(), "HDMI-9")))
        self.assertFalse(os.path.exists(os.path.join(self.share.widgets_dir(), "..", "evil")))

    def test_matugen_app_overrides_are_neither_exported_nor_imported(self):
        apps = os.path.join(self.tmp, "config", "taurus", "matugen", "apps", "kitty"); os.makedirs(apps)
        open(os.path.join(apps, "app.json"), "w").write("{}")
        self.assertNotIn("matugen", json.dumps(self.export()))
        self.run_import(self.write_bundle(matugen={"apps": {"kitty": {"integrate": "x"}}}), "--apply")
        self.assertEqual(os.listdir(apps), ["app.json"])


class RoundTripTests(ShareBase):
    def test_export_then_import_on_a_fresh_install(self):
        s = copy.deepcopy(DEFAULTS); s["bar"]["height"] = 55; s["dock"]["autohide"] = True
        s["bar"]["modules"]["left"] = ["workspaces"]
        self.write_settings(s)
        os.makedirs(self.share.themes_dir())
        json.dump(dict(THEME, name="Mine"), open(os.path.join(self.share.themes_dir(), "Mine.json"), "w"))
        bundle = self.export()
        # a fresh machine
        self.write_settings(copy.deepcopy(DEFAULTS))
        subprocess.run(["rm", "-rf", self.share.themes_dir()])
        path = os.path.join(self.tmp, "rt.json"); json.dump(bundle, open(path, "w"))
        self.assertEqual(self.run_import(path, "--apply")[0], 0)
        got = self.settings()
        self.assertEqual((got["bar"]["height"], got["dock"]["autohide"], got["bar"]["modules"]["left"]),
                         (55, True, ["workspaces"]))
        self.assertEqual(os.listdir(self.share.themes_dir()), ["Mine.json"])


if __name__ == "__main__":
    unittest.main(verbosity=1)

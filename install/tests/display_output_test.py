#!/usr/bin/env python3
"""display-output.py against a fake niri: mode list, apply, and the marked block in output.kdl."""
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "src" / "scripts" / "display-output.py"
OUTPUTS = {"DP-4": {"name": "DP-4", "make": "Samsung", "model": "Odyssey", "vrr_supported": True, "vrr_enabled": True,
                    "current_mode": 1, "is_custom_mode": False,
                    "modes": [{"width": 3840, "height": 2160, "refresh_rate": 60000},
                              {"width": 3840, "height": 2160, "refresh_rate": 143990},
                              {"width": 1920, "height": 1080, "refresh_rate": 60000}],
                    "logical": {"x": 0, "y": 0, "width": 3840, "height": 2160, "scale": 1.25, "transform": "_90"}}}


class DisplayOutputTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        self.log = self.tmp / "niri.log"
        fake = bin_dir / "niri"
        fake.write_text('#!/bin/sh\nif [ "$1" = msg ] && [ "$2" = --json ]; then cat "%s"; exit 0; fi\n'
                        'echo "$@" >> "%s"\nexit 0\n' % (self.tmp / "outputs.json", self.log))
        fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
        (self.tmp / "outputs.json").write_text(json.dumps(OUTPUTS))
        self.kdl = self.tmp / "output.kdl"
        self.env = dict(os.environ, PATH="%s:%s" % (bin_dir, os.environ["PATH"]), TAURUS_NIRI_OUTPUT_FILE=str(self.kdl),
                        XDG_STATE_HOME=str(self.tmp / "state"), TAURUS_SKIP_VALIDATE="1")

    def run_script(self, *args):
        return subprocess.run([sys.executable, "-I", str(SCRIPT), *args], capture_output=True, text=True, env=self.env)

    def test_info_groups_modes_by_resolution(self):
        out = json.loads(self.run_script("info").stdout)[0]
        self.assertEqual([(r["width"], r["rates"]) for r in out["resolutions"]], [(3840, [143990, 60000]), (1920, [60000])])
        self.assertEqual(out["current"], {"width": 3840, "height": 2160, "refresh": 143990})
        self.assertEqual((out["transform"], out["vrr_supported"], out["vrr_mode"]), ("90", True, "always"))

    def test_apply_calls_niri(self):
        res = self.run_script("apply", "DP-4", "--mode", "3840x2160@143.990", "--vrr", "off", "--transform", "180")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.log.read_text().split("\n")[:3],
                         ["msg output DP-4 mode 3840x2160@143.990", "msg output DP-4 transform 180", "msg output DP-4 vrr off"])

    def test_games_mode_is_on_demand_with_a_window_rule(self):
        res = self.run_script("apply", "DP-4", "--vrr", "games")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.log.read_text().strip(), "msg output DP-4 vrr on --on-demand")
        rule = self.kdl.read_text()
        self.assertIn("window-rule", rule)
        self.assertIn("variable-refresh-rate true", rule)
        self.assertEqual(json.loads(self.run_script("info").stdout)[0]["vrr_mode"], "games")
        self.assertEqual(self.run_script("persist", "DP-4").returncode, 0)
        self.assertIn("variable-refresh-rate on-demand=true", self.kdl.read_text())
        # a second run keeps the rule block (it may have been edited) and does not duplicate it
        self.run_script("apply", "DP-4", "--vrr", "games")
        self.assertEqual(self.kdl.read_text().count("taurus vrr games >>>"), 1)

    def test_always_and_off_modes(self):
        self.run_script("apply", "DP-4", "--vrr", "always")
        self.run_script("apply", "DP-4", "--vrr", "off")
        self.assertEqual(self.log.read_text().split("\n")[:2], ["msg output DP-4 vrr on", "msg output DP-4 vrr off"])
        self.assertEqual(json.loads(self.run_script("info").stdout)[0]["vrr_mode"], "off")
        self.run_script("persist", "DP-4")
        self.assertNotIn("variable-refresh-rate", self.kdl.read_text())

    def test_apply_rejects_bad_input(self):
        self.assertNotEqual(self.run_script("apply", "DP-4", "--mode", "x; rm").returncode, 0)
        self.assertNotEqual(self.run_script("apply", "DP-9", "--vrr", "on").returncode, 0)

    def test_persist_writes_and_replaces_marked_block(self):
        self.kdl.write_text('output "eDP-1" {\n    scale 1.0\n}\n')
        for _ in range(2):
            res = self.run_script("persist", "DP-4")
            self.assertEqual(res.returncode, 0, res.stderr)
        text = self.kdl.read_text()
        self.assertEqual(text.count("taurus output DP-4 >>>"), 1)
        self.assertIn('mode "3840x2160@143.990"', text)
        self.assertIn("scale 1.25", text)
        self.assertIn('transform "90"', text)
        self.assertIn("variable-refresh-rate", text)
        self.assertTrue(text.startswith('output "eDP-1"'))

    def test_persist_never_duplicates_a_users_own_block(self):
        self.kdl.write_text('output "DP-4" {\n    scale 2\n}\n')
        res = self.run_script("persist", "DP-4")
        self.assertEqual(res.returncode, 3)
        self.assertEqual(self.kdl.read_text(), 'output "DP-4" {\n    scale 2\n}\n')


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Contract between this layer and the subaud starter it sits on.

Run directly:  python3 tests/setup-contract.test.py
With the starter:  STARTER_TOML=<starter>/kempt.toml python3 tests/setup-contract.test.py

This repo's kempt.toml is a user layer on subaud-tools/starter, which owns the
suite tools (with their release setup: hooks, plugins, channels, services and
skills), pi and its base extensions, nvim, and the base Ghostty and yazi
configs. kempt refuses two layers linking one path, installing one binary or
running one service with different definitions, so the layer declares none of
what the starter does. Offline, this checks the layer's own shape; with
STARTER_TOML set it also checks the layer against that starter manifest.
"""

import os
import pathlib
import subprocess
import tomllib
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent
LAYER = tomllib.loads((REPO / "kempt.toml").read_text())
STARTER_TOML = os.environ.get("STARTER_TOML")
STARTER = tomllib.loads(pathlib.Path(STARTER_TOML).expanduser().read_text()) if STARTER_TOML else None

# Starter packages this layer's packages need by their unqualified name.
FROM_STARTER = {"pi", "muster"}
# The family-internal skills, each linked as its own folder for pi.
FAMILY_SKILLS = ["building-a-tools-family-tool", "releasing-a-tools-family-tool", "tools-family-onboarding"]
PI_PERMISSIONS = "~/.pi/agent/extensions/pi-permission-system/config.json"


def packages(doc):
    return doc.get("packages", {})


def needs_closure(names, pkgs):
    seen, todo = set(), list(names)
    while todo:
        n = todo.pop()
        if n in seen:
            continue
        seen.add(n)
        if n in pkgs:
            todo.extend(pkgs[n].get("needs", []))
    return seen


def merges(pkg, file):
    return [m for m in pkg.get("json-merge", []) if m["file"] == file]


def walk(value):
    if isinstance(value, dict):
        for k, v in value.items():
            yield k
            yield from walk(v)
    elif isinstance(value, list):
        for v in value:
            yield from walk(v)
    else:
        yield value


def exclusive(doc):
    """The targets kempt lets only one layer declare: link destinations,
    binaries and services."""
    out = set()
    for pkg in packages(doc).values():
        for s in pkg.get("symlink", []):
            out.add(("symlink", os.path.normpath(s["to"])))
        for d in pkg.get("download", []):
            out.add(("binary", d.get("bin", d["tool"])))
        for s in pkg.get("service", []):
            out.add(("service", s["label"]))
    return out


class LayerContract(unittest.TestCase):
    def test_is_a_user_layer_on_spec_2(self):
        self.assertEqual(LAYER["kempt"]["spec"], 2)
        self.assertEqual(LAYER["kempt"].get("layer"), "user")

    def test_no_layer_package_shadows_a_starter_one_it_needs(self):
        # An unqualified need names the layer's own package first, so a layer
        # package named pi or muster would take the place of the starter's.
        for name in FROM_STARTER:
            self.assertNotIn(name, packages(LAYER))

    def test_needs_resolve(self):
        pkgs = packages(LAYER)
        for name, pkg in pkgs.items():
            for need in pkg.get("needs", []):
                self.assertTrue(need in pkgs or need in FROM_STARTER, f"{name} needs {need}")

    def test_suite_tools_come_from_the_starter(self):
        for name, pkg in packages(LAYER).items():
            self.assertFalse(pkg.get("download"), f"{name}: downloads are the starter's")
            self.assertNotIn("managed-file", pkg, name)
            for line in pkg.get("line-in-file", []):
                self.assertNotIn(line["file"], ("~/.tmux.conf", "~/.zshrc"), f"{name}: {line['line']}")
            for m in pkg.get("json-merge", []):
                tokens = [t for t in walk(m.get("merge", {})) if isinstance(t, str)]
                self.assertFalse([t for t in tokens if t.endswith("@subaud-tools")], f"{name}: release-owned plugin")
                self.assertFalse([t for t in tokens if " hook " in t or "casebook " in t], f"{name}: release-owned hook")
                self.assertFalse([r for r in m.get("remove", []) if r.startswith(("enabledPlugins.", "mcpServers."))], f"{name}: release-owned removal")
            for m in pkg.get("toml-merge", []):
                self.assertNotEqual(m["file"], "~/.codex/config.toml", f"{name}: release-owned Codex MCP")

    def test_muster_in_pi_stays_here(self):
        # muster's release declares neither its pi channel nor its pi MCP server.
        channels = {}
        for name, pkg in packages(LAYER).items():
            for m in pkg.get("json-merge", []):
                for server in m.get("merge", {}).get("channelServers", {}):
                    channels.setdefault(server, []).append(name)
        self.assertEqual(channels, {"muster-channel": ["pi-channels"]})
        pkg = packages(LAYER)["pi-channels"]
        self.assertEqual(pkg["needs"], ["pi", "muster"])
        mcp = merges(pkg, "~/.config/mcp/mcp.json")
        self.assertEqual([m["merge"] for m in mcp], [{"mcpServers": {"muster": {"command": "muster", "args": ["mcp"]}}}])

    def test_pi_personal_lists_are_paired(self):
        pkg = packages(LAYER)["pi-personal"]
        self.assertEqual(pkg["needs"], ["pi"])
        installed = [e for i in pkg.get("install", []) for e in i.get("pi", [])]
        settings = merges(pkg, "~/.pi/agent/settings.json")
        listed = [e for m in settings for e in m.get("merge", {}).get("packages", [])]
        self.assertEqual(installed, listed)
        self.assertEqual(len(listed), len(set(listed)))
        self.assertEqual([m.get("arrays") for m in settings], ["replace"])
        self.assertEqual(settings[0]["merge"]["skills"], [])
        for name, other in packages(LAYER).items():
            if name != "pi-personal":
                self.assertFalse([i for i in other.get("install", []) if "pi" in i], name)
                self.assertFalse(merges(other, "~/.pi/agent/settings.json"), name)

    def test_pi_personal_permissions(self):
        perms = merges(packages(LAYER)["pi-personal"], PI_PERMISSIONS)
        self.assertEqual(len(perms), 1)
        self.assertEqual(perms[0].get("arrays"), "replace")
        self.assertIs(perms[0]["merge"]["yoloMode"], True)
        self.assertEqual(perms[0]["merge"]["promptAnswerers"], ["pi-hail"])

    def test_family_skills_link_each_folder(self):
        pkg = packages(LAYER)["family-skills"]
        links = [(s["from"], s["to"]) for s in pkg["symlink"]]
        self.assertEqual(links, [(f"config/pi/skills/{n}", f"~/.pi/agent/skills/{n}") for n in FAMILY_SKILLS])
        tracked = subprocess.run(["git", "ls-files", "config/pi/skills"], cwd=REPO, capture_output=True, text=True, check=True).stdout.split()
        self.assertEqual(sorted({p.split("/")[3] for p in tracked}), FAMILY_SKILLS)

    def test_claude_installs_its_cli(self):
        pkg = packages(LAYER)["claude"]
        self.assertIn("claude-code", [c for i in pkg.get("install", []) for c in i.get("brew", {}).get("casks", [])])
        self.assertIn({"command-exists": "claude", "only": {"os": "darwin"}}, pkg["verify"])

    def test_linux_checks_each_npm_cli_after_installing_it(self):
        # kempt re-checks a verify after apply only in a package that changed
        # something, and runs steps in written order. So on Linux, where claude
        # comes from npm, it is checked in workspace-linux after its npm step,
        # and the shared claude package checks only on a Mac.
        pkgs = packages(LAYER)
        for name, cli in (("claude", "claude"),):
            self.assertIn({"command-exists": cli, "only": {"os": "darwin"}}, pkgs[name]["verify"], name)
            self.assertNotIn({"command-exists": cli}, pkgs[name]["verify"], name)
        ws = pkgs["workspace-linux"]
        self.assertEqual(ws["only"], {"os": "linux"})
        self.assertNotIn("pi", needs_closure(["workspace-linux"], pkgs))  # a first apply's blocked pi extensions must not hold it back
        text = (REPO / "kempt.toml").read_text()
        block = text[text.index("\n[packages.workspace-linux]\n"):]
        block = block[: block.index("\n[", 1)]
        npm_at = block.index('npm = ["@anthropic-ai/claude-code"]')
        for cli in ("claude",):
            self.assertGreater(block.index(f'command-exists = "{cli}"'), npm_at, cli)

    def test_anonymous_layer_needs_no_identity(self):
        text = (REPO / "kempt.toml").read_text()
        for needle in ("/Users/", "Fundamental-Technologies", "~/GitHub/", "~/dotfiles/"):
            self.assertFalse(needle in text, f"kempt.toml names {needle}")
        tracked = subprocess.run(
            ["git", "ls-files", "config/pi/skills", "docs", "README.md", "CLAUDE.md"],
            cwd=REPO, capture_output=True, text=True, check=True,
        ).stdout.split()
        name = "C" "ourt"  # split so this file doesn't name it either
        named = [path for path in tracked if name in (REPO / path).read_text()]
        self.assertFalse(named, f"these tracked files name a person: {named}")

    def test_profiles(self):
        profiles = LAYER["profiles"]
        self.assertEqual(profiles["developer"]["packages"], ["core", "terminal", "markedit", "claude", "swiftbar", "family-skills", "pi-personal", "pi-channels"])
        self.assertEqual(profiles["workspace"]["packages"], ["core", "terminal", "claude", "family-skills", "pi-personal", "pi-channels", "workspace-linux"])
        self.assertEqual(profiles["minimal"]["packages"], ["core"])
        for profile in profiles.values():
            for name in profile["packages"]:
                self.assertIn(name, packages(LAYER))
                self.assertNotIn(name, ("pi-llama", "session-themes"))

    @unittest.skipUnless(STARTER, "STARTER_TOML not set")
    def test_nothing_the_starter_declares(self):
        self.assertEqual(exclusive(LAYER) & exclusive(STARTER), set())

    @unittest.skipUnless(STARTER, "STARTER_TOML not set")
    def test_needs_from_the_starter_exist_there(self):
        for name in FROM_STARTER:
            self.assertIn(name, packages(STARTER))

    @unittest.skipUnless(STARTER, "STARTER_TOML not set")
    def test_pi_personal_adds_to_the_starters_pi(self):
        base = [e for i in packages(STARTER)["pi"].get("install", []) for e in i.get("pi", [])]
        mine = [e for i in packages(LAYER)["pi-personal"].get("install", []) for e in i.get("pi", [])]
        self.assertEqual(set(base) & set(mine), set())


if __name__ == "__main__":
    unittest.main()

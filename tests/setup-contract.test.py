#!/usr/bin/env python3
"""Contract between the dotfiles manifests and the family's release-owned setup.

Run directly:  python3 tests/setup-contract.test.py

Family tools publish their own hooks, plugins, channels, services and skills in
a setup bundle beside each binary; kempt binds it to the download that says
`setup = true`. This guards the dotfiles side of that contract offline: which
downloads opt in, that nothing the bundles own is copied here as well, and that
the pi package lists each package declares stay paired. It reads only the
manifests in this checkout; release identities are checked during acceptance.
"""

import pathlib
import tomllib
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent
BASE = tomllib.loads((REPO / "kempt.toml").read_text())
HOME = tomllib.loads((REPO / "layers/home/kempt.toml").read_text())

# Downloads whose release publishes a setup bundle.
SETUP_TOOLS = {"proj", "muster", "galley", "muda", "sift", "imprint", "casebook", "cull", "diazo", "hail"}
# Ordinary binary-only downloads.
PLAIN_TOOLS = {"scratch", "creel"}
# The developer selection as it was saved before this change.
SAVED_DEVELOPER = ["core", "terminal", "nvim", "markedit", "claude", "swiftbar", "codex", "muster", "galley", "sift", "muda", "pi", "pi-channels"]


def packages(doc):
    return doc.get("packages", {})


def all_packages():
    return {**packages(BASE), **{f"home/{k}": v for k, v in packages(HOME).items()}}


def downloads():
    for name, pkg in all_packages().items():
        for d in pkg.get("download", []):
            yield name, d


def needs_closure(names, pkgs):
    seen, todo = set(), list(names)
    while todo:
        n = todo.pop()
        if n in seen:
            continue
        seen.add(n)
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


class SetupContract(unittest.TestCase):
    def test_manifests_use_spec_2(self):
        self.assertEqual(BASE["kempt"]["spec"], 2)
        self.assertEqual(HOME["kempt"]["spec"], 2)

    def test_one_download_per_binary(self):
        bins = [d["bin"] for _, d in downloads()]
        self.assertEqual(sorted(bins), sorted(set(bins)))
        self.assertEqual(set(bins), SETUP_TOOLS | PLAIN_TOOLS)

    def test_setup_opt_in(self):
        for name, d in downloads():
            if d["tool"] in SETUP_TOOLS:
                self.assertIs(d.get("setup"), True, f"{name}: {d['tool']} must take its release setup")
            else:
                self.assertNotIn("setup", d, f"{name}: {d['tool']} is an ordinary download")

    def test_tackle_downloads_name_the_product(self):
        for name, d in downloads():
            if d["site"] == "tackle.tools":
                self.assertEqual(d.get("product"), "tackle", f"{name}: {d['tool']}")

    def test_no_copied_release_setup(self):
        channels = {}
        for name, pkg in all_packages().items():
            self.assertNotIn("managed-file", pkg, name)
            if any(d.get("setup") for d in pkg.get("download", [])):
                self.assertNotIn("service", pkg, f"{name}: its release owns the service")
            for line in pkg.get("line-in-file", []):
                self.assertNotIn(line["file"], ("~/.tmux.conf", "~/.zshrc"), f"{name}: {line['line']}")
            for m in pkg.get("json-merge", []):
                tokens = [t for t in walk(m.get("merge", {})) if isinstance(t, str)]
                self.assertFalse([t for t in tokens if t.endswith("@subaud-tools")], f"{name}: release-owned plugin")
                self.assertFalse([t for t in tokens if " hook " in t or "casebook " in t], f"{name}: release-owned hook")
                self.assertFalse([r for r in m.get("remove", []) if r.startswith(("enabledPlugins.", "mcpServers."))], f"{name}: release-owned removal")
                for server in m.get("merge", {}).get("channelServers", {}):
                    channels.setdefault(server, []).append(name)
            for m in pkg.get("toml-merge", []):
                self.assertNotEqual(m["file"], "~/.codex/config.toml", f"{name}: release-owned Codex MCP")
        # Muster's release does not register its pi channel; that one stays here.
        self.assertEqual(channels, {"muster-channel": ["pi-channels"]})

    def test_muster_pi_registration_stays_with_dotfiles(self):
        pkgs = packages(BASE)
        mcp = merges(pkgs["muster"], "~/.config/mcp/mcp.json")
        self.assertEqual([m["merge"] for m in mcp], [{"mcpServers": {"muster": {"command": "muster", "args": ["mcp"]}}}])
        self.assertEqual(pkgs["pi-channels"]["needs"], ["pi", "muster", "galley", "sift", "imprint", "muda"])

    def test_claude_installs_its_cli(self):
        pkg = packages(BASE)["claude"]
        self.assertIn("claude-code", [c for i in pkg.get("install", []) for c in i.get("brew", {}).get("casks", [])])
        self.assertIn({"command-exists": "claude"}, pkg["verify"])

    def test_pi_lists_are_paired(self):
        for name, pkg in all_packages().items():
            installed = [e for i in pkg.get("install", []) for e in i.get("pi", [])]
            listed = [e for m in merges(pkg, "~/.pi/agent/settings.json") for e in m.get("merge", {}).get("packages", [])]
            self.assertEqual(installed, listed, name)
            self.assertEqual(len(listed), len(set(listed)), name)
        composed = [e for p in all_packages().values() for m in merges(p, "~/.pi/agent/settings.json") for e in m.get("merge", {}).get("packages", [])]
        self.assertEqual(len(composed), len(set(composed)))

    def test_home_casebook_needs_pi(self):
        self.assertIn("pi", packages(HOME)["casebook"].get("needs", []))

    def test_new_public_packages_note_their_access(self):
        for name in ("diazo", "hail"):
            pkg = packages(BASE)[name]
            self.assertTrue(any("entitle" in n for n in pkg.get("notes", [])), name)

    def test_anonymous_base_needs_no_identity(self):
        for path in ("kempt.toml", "layers/home/kempt.toml"):
            text = (REPO / path).read_text()
            for needle in ("/Users/", "Fundamental-Technologies", "~/GitHub/", "~/dotfiles/"):
                self.assertFalse(needle in text, f"{path} names {needle}")

    def test_base_skills_list_is_explicitly_empty(self):
        skills = [m for m in merges(packages(BASE)["pi"], "~/.pi/agent/settings.json") if "skills" in m["merge"]]
        self.assertEqual([(m["merge"]["skills"], m.get("arrays")) for m in skills], [([], "replace")])

    def test_profiles(self):
        profiles = BASE["profiles"]
        developer = profiles["developer"]["packages"]
        for name in ("diazo", "imprint", "hail"):
            self.assertIn(name, developer)
        for name in ("pi-llama", "session-themes"):
            self.assertNotIn(name, developer)
        self.assertEqual(profiles["minimal"]["packages"], ["core"])
        self.assertEqual(HOME["profiles"]["home"]["packages"], ["casebook", "cull"])

    def test_every_package_selects_alone(self):
        pkgs = packages(BASE)
        for name in pkgs:
            needs_closure([name], pkgs)

    def test_saved_selection_gains_nothing_implicitly(self):
        closure = needs_closure(SAVED_DEVELOPER, packages(BASE))
        self.assertEqual(closure, set(SAVED_DEVELOPER) | {"imprint"})


if __name__ == "__main__":
    unittest.main()

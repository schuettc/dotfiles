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
import subprocess
import tomllib
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent
BASE = tomllib.loads((REPO / "kempt.toml").read_text())
HOME = tomllib.loads((REPO / "layers/home/kempt.toml").read_text())

# Downloads whose release publishes a setup bundle.
SETUP_TOOLS = {"proj", "muster", "galley", "muda", "sift", "imprint", "casebook", "cull", "diazo", "hail"}
# Ordinary binary-only downloads.
PLAIN_TOOLS = {"scratch", "creel"}
# Retired registrations whose cleanup the releases do not carry, so the
# packages that select those tools keep removing them here.
RETAINED_CLEANUP = {
    "sift": ("~/.claude/settings.json", "extraKnownMarketplaces.tackle"),
    "imprint": ("~/.claude/settings.json", "extraKnownMarketplaces.tackle"),
    "home/cull": ("~/.claude/settings.json", "extraKnownMarketplaces.tackle"),
    "diazo": ("~/.claude.json", "mcpServers.diazo"),
}
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
                retained = {RETAINED_CLEANUP[name][1]} if name in RETAINED_CLEANUP else set()
                self.assertFalse([r for r in m.get("remove", []) if r.startswith(("enabledPlugins.", "mcpServers.")) and r not in retained], f"{name}: release-owned removal")
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
        self.assertIn({"command-exists": "claude", "only": {"os": "darwin"}}, pkg["verify"])

    def test_linux_checks_each_npm_cli_after_installing_it(self):
        # kempt re-checks a verify after apply only in a package that changed
        # something, and runs steps in written order. So on Linux, where claude
        # and codex come from npm, each is checked in workspace-linux after its
        # npm step, and the shared claude and codex packages check only on a Mac.
        pkgs = packages(BASE)
        for name, cli in (("claude", "claude"), ("codex", "codex")):
            self.assertIn({"command-exists": cli, "only": {"os": "darwin"}}, pkgs[name]["verify"], name)
            self.assertNotIn({"command-exists": cli}, pkgs[name]["verify"], name)
        ws = pkgs["workspace-linux"]
        self.assertEqual(ws["only"], {"os": "linux"})
        self.assertNotIn("pi", ws["needs"])  # a first apply's blocked pi extensions must not hold it back
        text = (REPO / "kempt.toml").read_text()
        block = text[text.index("\n[packages.workspace-linux]\n"):]
        block = block[: block.index("\n[", 1)]
        npm_at = block.index('npm = ["@anthropic-ai/claude-code", "@openai/codex"]')
        for cli in ("claude", "codex"):
            self.assertGreater(block.index(f'command-exists = "{cli}"'), npm_at, cli)

    def test_pi_lists_are_paired(self):
        for name, pkg in all_packages().items():
            installed = [e for i in pkg.get("install", []) for e in i.get("pi", [])]
            listed = [e for m in merges(pkg, "~/.pi/agent/settings.json") for e in m.get("merge", {}).get("packages", [])]
            self.assertEqual(installed, listed, name)
            self.assertEqual(len(listed), len(set(listed)), name)
        composed = [e for p in all_packages().values() for m in merges(p, "~/.pi/agent/settings.json") for e in m.get("merge", {}).get("packages", [])]
        self.assertEqual(len(composed), len(set(composed)))

    def test_retired_registrations_still_removed(self):
        pkgs = all_packages()
        for name, (file, path) in RETAINED_CLEANUP.items():
            removed = [r for m in merges(pkgs[name], file) for r in m.get("remove", [])]
            self.assertIn(path, removed, name)

    def test_hail_does_not_wait_for_pi(self):
        # On a fresh machine pi is incomplete after its first apply (its
        # extensions step plans blocked until pi is installed), and kempt holds
        # back whatever needs an incomplete package. hail's release setup would
        # then fail the first apply. Its pi end comes with pi, which every
        # profile that has hail selects.
        pkgs, profiles = packages(BASE), BASE["profiles"]
        self.assertNotIn("pi", needs_closure(["hail"], pkgs))
        for name, profile in profiles.items():
            if "hail" in profile["packages"]:
                self.assertIn("pi", profile["packages"], name)

    def test_skills_link_comes_before_the_skills_written_into_it(self):
        # Releases write their skills into ~/.pi/agent/skills; that path must
        # already be the link to config/pi/skills, or the link step moves their
        # files aside. The link is in pi-skills, which needs nothing that can be
        # incomplete on a first apply, and every tool that writes there needs it.
        pkgs = packages(BASE)
        link = {"link": "~/.pi/agent/skills", "target": "config/pi/skills"}
        owners = [n for n, p in pkgs.items() for v in p.get("verify", []) if v.get("symlink-target") == link]
        self.assertEqual(owners, ["pi-skills"])
        self.assertEqual(pkgs["pi-skills"]["needs"], ["core"])
        self.assertIn("pi-skills", pkgs["pi"]["needs"])
        for name in ("galley", "muda", "sift", "imprint", "diazo"):
            self.assertIn("pi-skills", pkgs[name]["needs"], name)
            self.assertNotIn("pi", needs_closure([name], pkgs), name)
        for name, profile in BASE["profiles"].items():
            if "pi" in profile["packages"]:
                self.assertIn("pi-skills", profile["packages"], name)

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
        tracked = subprocess.run(
            ["git", "ls-files", "config/pi/skills", "config/pi/agents", "docs", "README.md", "CLAUDE.md"],
            cwd=REPO, capture_output=True, text=True, check=True,
        ).stdout.split()
        name = "C" "ourt"  # split so this file doesn't name it either
        named = [path for path in tracked if name in (REPO / path).read_text()]
        self.assertFalse(named, f"these tracked files name a person: {named}")

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
        # pi-skills is pi's skills link, moved into a package of its own.
        closure = needs_closure(SAVED_DEVELOPER, packages(BASE))
        self.assertEqual(closure, set(SAVED_DEVELOPER) | {"imprint", "pi-skills"})


if __name__ == "__main__":
    unittest.main()

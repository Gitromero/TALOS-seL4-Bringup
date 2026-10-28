"""Repository hygiene: links, permissions, caches, stale names, privacy, hashes."""
import hashlib
import os
import re
import socket
import subprocess
import unittest
from urllib.parse import unquote

from paths import REPO

# Records of what happened, kept as written; they may name retired tools. So
# may docs/tooling.md, which explains why they were replaced.
HISTORICAL = ("history/", "reports/", "docs/tooling.md")
RETIRED = ["scripts/pf", "pf flash", "pf status", "pf console", "usb-flash.sh", "network-flash.sh",
           "serial-share.py", "SETUP.md", "FLASHING.md", "NETBOOT.md", "SHARED_CONSOLE.md",
           "PERIPHERALS.md", "BRINGUP_GUIDE.md", "BUILD_PROVENANCE.md", "ARTIFACT_INTEGRITY.md",
           "FIRMWARE_COMPATIBILITY.md", "TROUBLESHOOTING.md", "context/SEL4_BRINGUP_CONTEXT",
           "scripts/test-installer.sh", "(rust-root-task/", "board/discovery/build.sh"]


def tracked():
    out = subprocess.run(["git", "ls-files", "-s"], cwd=REPO, stdout=subprocess.PIPE, text=True, check=True)
    files = {}
    for line in out.stdout.splitlines():
        path = line.split("\t", 1)[1]
        if (REPO / path).exists():          # skip files deleted in the working tree
            files[path] = None
    # New files not yet added count too.
    out = subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], cwd=REPO,
                         stdout=subprocess.PIPE, text=True, check=True)
    files.update(dict.fromkeys(out.stdout.splitlines()))
    # Modes as they are on disk, i.e. as the next commit records them.
    return {p: "100755" if os.access(REPO / p, os.X_OK) else "100644" for p in files}


def text_files():
    for path in tracked():
        data = (REPO / path).read_bytes()
        if b"\0" not in data[:4096]:
            yield path, data.decode(errors="replace")


def anchors(markdown):
    """GitHub heading anchors of a Markdown document."""
    seen, result = {}, set()
    for heading in re.findall(r"^#{1,6} +(.+?) *#*$", markdown, re.M):
        slug = re.sub(r"[^\w\- ]", "", heading.replace("`", "").lower()).replace(" ", "-")
        n = seen.get(slug, 0)
        seen[slug] = n + 1
        result.add(slug if n == 0 else f"{slug}-{n}")
    return result


class Repository(unittest.TestCase):
    def test_markdown_links_and_anchors_resolve(self):
        problems = []
        for path, text in text_files():
            if not path.endswith(".md"):
                continue
            text_no_code = re.sub(r"```.*?```", "", text, flags=re.S)
            for target in re.findall(r"\]\(([^)\s]+)\)", text_no_code):
                if re.match(r"[a-z]+:", target):
                    continue                   # external URL
                file_part, _, anchor = target.partition("#")
                resolved = (REPO / path).parent / unquote(file_part) if file_part else REPO / path
                if not resolved.exists():
                    problems.append(f"{path}: missing {target}")
                elif anchor and resolved.suffix == ".md" and anchor not in anchors(resolved.read_text()):
                    problems.append(f"{path}: no heading for #{anchor} in {file_part or path}")
        self.assertEqual(problems, [])

    def test_tools_are_executable_with_a_shebang(self):
        files = tracked()
        tools = [p for p in files if p.endswith(".sh") or p == "scripts/board.py"
                 or p == "scripts/privacy_audit.py"]
        for path in tools:
            with self.subTest(path=path):
                self.assertEqual(files[path], "100755")
                self.assertTrue((REPO / path).read_text().startswith("#!"))

    def test_no_bytecode_tracked(self):
        self.assertEqual([p for p in tracked() if "__pycache__" in p or p.endswith(".pyc")], [])

    def test_no_references_to_retired_names(self):
        problems = []
        for path, text in text_files():
            if path.startswith(HISTORICAL) or path == "tests/test_repository.py":
                continue
            for name in RETIRED:
                if name in text:
                    problems.append(f"{path}: {name}")
        self.assertEqual(problems, [])

    def test_no_host_specific_data(self):
        home = os.path.expanduser("~")
        host = socket.gethostname()
        problems = []
        for path, text in text_files():
            if home and home != "/" and home in text:
                problems.append(f"{path}: home directory")
            if len(host) >= 4 and re.search(rf"\b{re.escape(host)}\b", text):
                problems.append(f"{path}: host name")
        self.assertEqual(problems, [])

    def test_main_repository_is_not_named(self):
        # Owner decision (README, "Publication status"): refer to it only as
        # "the main TALOS repository".
        name = "".join(["And", "uril"])
        self.assertEqual([p for p, text in text_files() if name.lower() in text.lower()], [])

    def test_shipped_files_match_their_hashes(self):
        for line in (REPO / "images" / "SHA256SUMS").read_text().splitlines():
            digest, name = line.split(maxsplit=1)
            name = name.lstrip("*")
            with self.subTest(file=name):
                self.assertEqual(hashlib.sha256((REPO / name).read_bytes()).hexdigest(), digest)


if __name__ == "__main__":
    unittest.main()

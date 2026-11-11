"""Offline patch-state and driver call-contract tests, not Cocoa/game acceptance."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import tarfile

ROOT = Path(__file__).resolve().parents[1]
NAME = "cyder-winemac-gl-front-buffer-present.patch"
PATCH = ROOT / "patches" / NAME
A6 = ROOT / "patches/a6-final-same-view-backing-sync.patch"
REL = Path("dlls/winemac.drv/opengl.c")
BUILD = (ROOT / "scripts/build-wine.sh").read_text()
CONFIG = json.loads((ROOT / "config/engine-release.json").read_text())


def run(args, **kwargs):
    return subprocess.run(args, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, **kwargs)


def check(result):
    assert result.returncode == 0, result.stdout
    return result.stdout


with tempfile.TemporaryDirectory(prefix="cyder-front-buffer-") as tmp:
    tmp = Path(tmp)
    tree = tmp / "source"
    source = tree / REL
    source.parent.mkdir(parents=True)
    pristine = (ROOT / "tests/fixtures/winemac-front-buffer/opengl.c").read_text()
    source.write_text(pristine)
    a6_gl = tmp / "a6-gl.patch"
    a6_gl.write_text("--- a/" + str(REL) + A6.read_text().split("--- a/" + str(REL), 1)[1])
    # The new patch must fail before A6, without leaving partially patched files.
    result = run(["patch", "--forward", "--batch", "--fuzz=0", "--dry-run",
                  "-d", str(tree), "-p1", "-i", str(PATCH)])
    assert result.returncode != 0, result.stdout
    assert source.read_text() == pristine
    check(run(["patch", "--forward", "--batch", "--fuzz=0", "-d", str(tree),
               "-p1", "-i", str(a6_gl)]))
    after_a6 = source.read_text()
    # Exercise the production function, rather than reimplementing its guard.
    apply_function = BUILD.split("apply_cyder_patch() {", 1)[1].split(
        "\nremove_obsolete_cyder_patch()", 1)[0]
    driver = tmp / "apply.sh"
    driver.write_text('set -euo pipefail\napply_cyder_patch() {' + apply_function +
                      '\napply_cyder_patch "$1"\n')
    env = dict(os.environ, WINE_SRC=str(tree), DRY_RUN="0")

    def apply(patch=PATCH):
        return run(["bash", str(driver), str(patch)], env=env)

    source.write_text(pristine)
    assert apply().returncode != 0
    assert source.read_text() == pristine
    source.write_text(after_a6)
    check(apply())
    complete = source.read_text()
    assert "all hunks verified" in check(apply())
    assert source.read_text() == complete
    # Every proper subset of the two hunks must fail closed, byte-for-byte.
    header, hunks = PATCH.read_text().split("@@ ", 1)
    hunks = ("@@ " + hunks).split("\n@@ ")
    for i in range(2):
        source.write_text(after_a6)
        one = tmp / "one.patch"
        one.write_text(header + (hunks[i] if i == 0 else "@@ " + hunks[i]))
        check(run(["patch", "--forward", "--batch", "--fuzz=0", "-d", str(tree),
                   "-p1", "-i", str(one)]))
        partial = source.read_bytes()
        result = apply()
        assert result.returncode != 0 and "Incomplete or incompatible" in result.stdout
        assert source.read_bytes() == partial
    # A marker in a comment must not masquerade as a complete application.
    source.write_text(after_a6 + "\n/* if (flags & GL_FLUSH_PRESENT) */\n")
    check(apply())
    assert source.read_text().count("client_surface_present(base->client);") == 2
    # An edited applied hunk must also fail, rather than be accepted by a marker.
    source.write_text(complete.replace("client_surface_present(base->client);", "/* missing present */", 1))
    before = source.read_bytes()
    assert apply().returncode != 0
    assert source.read_bytes() == before
    source.write_text(complete)
    # Compile and execute the exact patched functions with observable driver stubs.
    harness = (ROOT / "tests/fixtures/winemac-front-buffer/harness.c").read_text()
    code = tmp / "contract.c"
    code.write_text(harness.replace("/* PATCHED_FUNCTIONS */", complete))
    compiler = shutil.which("clang") or shutil.which("cc")
    assert compiler, "C compiler required for driver contract tests"
    check(run([compiler, "-std=c99", "-Wall", "-Wextra", "-Werror",
               str(code), "-o", str(tmp / "contract")]))
    check(run([str(tmp / "contract")]))
    # When the local CX26 archive exists, test the entire real A6 patch too.
    # The small checked-in fixture keeps the core regression test offline.
    archive = ROOT / "tools/archives/crossover-sources-26.3.0.tar.gz"
    if archive.is_file():
        full = tmp / "archive-source"
        with tarfile.open(archive) as tar:
            for name in ("cocoa_opengl.h", "macdrv_cocoa.h", "cocoa_opengl.m",
                         "cocoa_window.m", "window.c", "opengl.c"):
                target = full / "dlls/winemac.drv" / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(tar.extractfile("sources/wine/dlls/winemac.drv/" + name).read())
        original_gl = (full / REL).read_text()
        for name in ("macdrv_surface_flush", "macdrv_surface_swap"):
            start = pristine.rfind("static ", 0, pristine.index(name + "("))
            end = pristine.index("\n}", start) + 2
            assert pristine[start:end] in original_gl, "fixture differs from CX26.3"
        check(run(["patch", "--forward", "--batch", "--fuzz=0", "-d", str(full),
                   "-p1", "-i", str(A6)]))
        env["WINE_SRC"] = str(full)
        check(apply())
        combined = (full / REL).read_bytes()
        check(apply(A6))
        assert (full / REL).read_bytes() == combined
        check(apply())
        old_a6_probe = run(["patch", "--reverse", "--batch", "--dry-run", "-s",
                            "-d", str(full), "-p1", "-i", str(A6)])
        assert old_a6_probe.returncode != 0, "expected overlapping A6 reverse-probe failure"
        # The A6 live-tree regression must also pass after the new patch.
        # Give its production script an isolated ROOT with patched source.
        mirror = tmp / "a6-test"
        (mirror / "tests").mkdir(parents=True)
        shutil.copy(ROOT / "tests/test-winemac-a6-patch.sh", mirror / "tests")
        shutil.copy(ROOT / "tests/assert.sh", mirror / "tests")
        (mirror / "patches").symlink_to(ROOT / "patches", target_is_directory=True)
        (mirror / "scripts").symlink_to(ROOT / "scripts", target_is_directory=True)
        (mirror / "build/cx26/sources").mkdir(parents=True)
        (mirror / "build/cx26/sources/wine").symlink_to(full, target_is_directory=True)
        check(run(["bash", str(mirror / "tests/test-winemac-a6-patch.sh")]))
        print("PASS full A6 + front-buffer stack and repeat on archived CX26.3")
        # Also check every release patch together, rather than just the two
        # overlapping patches or a separately validated MapleStory subset.
        release = tmp / "release-source"
        paths = set()
        for patch_name in CONFIG["patches"]:
            text = (ROOT / "patches" / patch_name).read_text()
            paths.update(re.findall(r"^--- a/(\S+)", text, re.M))
            paths.update(re.findall(r"^\+\+\+ b/(\S+)", text, re.M))
        with tarfile.open(archive) as tar:
            for path in paths:
                target = release / path
                target.parent.mkdir(parents=True, exist_ok=True)
                try:
                    member = tar.getmember("sources/wine/" + path)
                except KeyError:
                    continue  # A patch may add a new file.
                target.write_bytes(tar.extractfile(member).read())
        env["WINE_SRC"] = str(release)
        for patch_name in CONFIG["patches"]:
            if patch_name == NAME:
                check(apply())
            else:
                check(run(["patch", "--forward", "--batch", "-s", "-d", str(release),
                           "-p1", "-i", str(ROOT / "patches" / patch_name)]))
        check(apply(A6))
        check(apply())
        print("PASS all ordered release-manifest patches on archived CX26.3")
    else:
        print("SKIP full-source A6 test: local CX26.3 archive absent")
    # Ordered canonical metadata must survive actual manifest generation.
    patches = CONFIG["patches"]
    assert patches.count(NAME) == 1
    assert patches.index(A6.name) < patches.index(NAME)
    calls = re.findall(r'^  apply_cyder_patch "\$OGOM/patches/([^"]+)"', BUILD, re.M)
    assert calls.count(NAME) == 1 and calls.index(A6.name) < calls.index(NAME)
    # Compare the relative order of all unconditional Cyder patches.
    assert [p for p in patches if p in calls] == [p for p in calls if p in patches]
    manifest = tmp / "manifest.json"
    check(run(["bash", str(ROOT / "scripts/write-engine-manifest.sh"),
               "--output", str(manifest), "--version",
               (ROOT / "config/engine-version.txt").read_text().strip(),
               "--ntdll-sha256", hashlib.sha256(b"offline fixture").hexdigest()]))
    assert json.loads(manifest.read_text())["patches"] == patches

print("PASS front-buffer order, repeat, partial, marker, manifest, and C call contracts")

#!/usr/bin/env python3
"""Offline release-facing pin audit, including negative regression cases.

Expected labels and MoltenVK variants come only from the two canonical configs.
The current schema records the variant filenames in notes; missing/ambiguous
notes fail closed rather than falling back to constants. No build tree, network,
Wine runtime, or third-party Python modules are needed.
"""

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = "config/engine-release.json"
VERSION = "config/engine-version.txt"
README = "README.md"
GUIDE = "docs/build-engine-from-scratch.zh-TW.md"
WORKFLOW = "docs/engine-development-test-workflow.zh-TW.md"
INTEGRATION = "docs/integration-with-cyder.md"
INCREMENTAL = "docs/incremental-build-and-patches.md"
ENV = "scripts/env-x86_64.sh"
INSTALLER = "scripts/install-moltenvk-dual-variant.sh"
PACKER = "scripts/pack-engine-artifact.sh"
RELEASE_SKILL = ".agents/skills/engine-release-pack/SKILL.md"
REQUIRED = [CONFIG, VERSION, README, GUIDE, WORKFLOW, INTEGRATION, INCREMENTAL,
            ENV, INSTALLER, PACKER, RELEASE_SKILL, "AGENTS.md", ".env.example",
            "patches/README.md"]

# These documents describe immutable releases or a superseded overlay design,
# not the current release target. Do not blanket-exempt docs/ or worklogs.
HISTORICAL_FILES = {
    "docs/cyder009-release.md": "Cyder009 release metadata and acceptance record",
    "docs/cyder011-to-cyder012-changelog.zh-TW.md": "Cyder011/Cyder012 archive and binary comparison",
    "docs/wineserver-teardown-hardening-cyder008.md": "Cyder007/Cyder008 teardown investigation",
    "docs/maplestory-classic-cx26-frame-walk-debug.md": "Cyder005/006/007 frame-walk investigation",
    "docs/moltenvk-timeline-wait-poll-app-overlay.md": "Pre-dual-variant Cyder007 app-overlay design",
    "docs/arm64-native-build-experiment-2026-09-21.zh-TW.md": "Dated 2026-09-21 arm64 experiment on Cyder012",
    "docs/maplestory-cx26-first-hit-materialize-findings.zh-TW.md": "Cyder012 first-hit measurement record",
    "docs/maplestory-cx26-wz-cache-experiments.zh-TW.md": "Cyder012 WZ cache experiment record",
    "docs/maplestory-exit-hang-20261029.zh-TW.md": "Dated 2026-10-29 exit-hang investigation on Cyder012",
    "docs/upstream-wine-11/test-runtime-kit-validation.md": "Cyder012-based PR2/PR3 test kit validation record",
}
HISTORICAL_SECTIONS = {
    "docs/maplestory-cx26-worklog.zh-TW.md": {
        "### 2026-08-15：將 full-video GStreamer 內嵌 Cyder011 engine artifact":
            "Dated record of the first embedded full-video release",
    },
}
# Exact lines only: legacy compatibility logic must not exempt nearby examples
# or defaults. New exceptions require a reason and a reviewable scope here.
HISTORICAL_LINES = {
    RELEASE_SKILL: {
        "  producing Cyder012+ release tarballs or repairing adhoc/broken graphics packs":
            "Dual-variant layout introduction threshold",
    },
    GUIDE: {
        "| 打包後缺少 versioned MoltenVK 或 shim | 未跑 `install-moltenvk-dual-variant.sh` | 組裝 dual layout 後再 pack；Cyder012+ 需要雙 real + `.real` + wait-poll shim |":
            "Dual-variant layout introduction threshold",
    },
    INTEGRATION: {
        "Cyder012+ ships a **dual-variant** MoltenVK layout: versioned reals":
            "Dual-variant layout introduction threshold",
    },
    "docs/upstream-wine-11/README.md": {
        '版本公告只是變更索引，不是 Cyder 相容性證明。本 PR 不升級 Wine base、不宣稱 CS2 已可玩、不替換使用者 runtime。保留現有 Cyder012 identity，正式打包前需按 repository 發行流程決定新版本識別。':
            "PR3 review record written against Cyder012",
    },
    README: {
        "The patch application is idempotent and can migrate a Cyder006 combined":
            "Supported migration from the obsolete combined frame-walk patch",
    },
    "patches/README.md": {
        "incremental Cyder006 source tree. It is removed before the two replacement":
            "Supported obsolete patch migration",
    },
    PACKER: {
        "# Cyder012+ dual-variant MoltenVK: two versioned reals + wait-poll shim + .real symlink.":
            "Dual-variant layout introduction threshold",
        "# Cyder008/009 kept the older single-real + shim pair without versioned siblings.":
            "Historical layout introduction",
        'if [[ "$ENGINE_VERSION_LABEL" == *Cyder008* || "$ENGINE_VERSION_LABEL" == *Cyder009* ]]; then':
            "Legacy single-real pack validation branch",
        'elif [[ "$ENGINE_VERSION_LABEL" == *Cyder012* || "$ENGINE_VERSION_LABEL" == *Cyder01[3-9]* || "$ENGINE_VERSION_LABEL" == *Cyder0[2-9]* ]]; then':
            "Dual-variant validation introduction threshold, not a release default",
    },
    "scripts/ensure-moltenvk-source.sh": {
        "  1.4.0)": "Checksum support for an explicit legacy source override",
    },
}

SEMVER = r"\d+\.\d+\.\d+"
LABEL = re.compile(r"\b(?:CX\d+(?:[.-]\d+){2}-W\d+-)?Cyder\d+(?:-rc\d+)?\b")
LIBRARY = re.compile(r"libMoltenVK-(" + SEMVER + r")\.dylib")
MVK_PIN = re.compile(
    r"(?:libMoltenVK-|moltenvk[-\s]+)[*`]*(" + SEMVER + r")\b"
    r"|MOLTENVK_VERSION(?:=|:-)[\"']?(" + SEMVER + r")\b"
    r"|[\"']?moltenvk(?:[_-]?version)?[\"']?\s*[:=]\s*[\"']?(" + SEMVER + r")\b"
    r"|(?:--default\s+|DEFAULT_VARIANT=[\"']?)(" + SEMVER + r")\b",
    re.IGNORECASE,
)


def read_corpus():
    # Required entrypoints may not disappear silently. Also discover future
    # docs, scripts and example files, including examples/ when it is added.
    paths = {ROOT / name for name in REQUIRED}
    paths.update(ROOT.glob("README*"))
    for directory in ("docs", "scripts", "examples", ".agents/skills"):
        paths.update(p for p in (ROOT / directory).rglob("*")
                     if p.is_file() and "__pycache__" not in p.parts)
    corpus = {}
    for path in sorted(paths):
        if not path.is_file():
            continue
        try:
            corpus[str(path.relative_to(ROOT))] = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue  # binary evidence (screenshots) carries no release claims
    return corpus


def current_lines(name, text):
    archived_level = None
    for number, line in enumerate(text.splitlines(), 1):
        heading = re.match(r"^(#{1,6})\s", line)
        if heading and archived_level is not None and len(heading[1]) <= archived_level:
            archived_level = None
        if line in HISTORICAL_SECTIONS.get(name, {}):
            archived_level = len(heading[1])
        if archived_level is None and line not in HISTORICAL_LINES.get(name, {}):
            yield number, line


def audit(corpus):
    errors = []
    missing = [name for name in REQUIRED if name not in corpus]
    if missing:
        return ["Missing required file: " + name for name in missing]
    try:
        contract = json.loads(corpus[CONFIG])
        label = contract["versionLabel"]
        if not isinstance(label, str) or not re.fullmatch(
                r"CX" + SEMVER + r"-W\d+-Cyder\d+(?:-rc\d+)?", label):
            raise ValueError("invalid versionLabel")
        notes = contract["notes"]
        if not isinstance(notes, str) or "Dual-variant MoltenVK ships" not in notes:
            raise ValueError("missing dual-variant MoltenVK contract")
        variants = set(LIBRARY.findall(notes))
        if len(variants) != 2:
            raise ValueError("expected two distinct versioned MoltenVK reals in notes")
    except (ValueError, KeyError, TypeError) as exc:
        return [f"Invalid canonical contract: {exc}"]

    if corpus[VERSION].splitlines() != [label]:
        errors.append(f"{VERSION}: label disagrees with {CONFIG}")
    short_label = label.split("-")[-1]
    allowed_labels = {label, re.sub(r"[ .()/]+", "-", label), short_label}
    # For rc labels, the bare Cyder generation remains valid in prose.
    allowed_labels.add(re.search(r"Cyder\d+", label)[0])

    for name, text in sorted(corpus.items()):
        if name in (CONFIG, VERSION) or name in HISTORICAL_FILES:
            continue
        for number, line in current_lines(name, text):
            for pin in LABEL.findall(line):
                if pin not in allowed_labels:
                    errors.append(f"{name}:{number}: engine pin {pin} != {label}")
            pins = {value for match in MVK_PIN.findall(line) for value in match if value}
            # MoltenVK-specific scripts also contain bare versions in case arms
            # and usage text. Audit those as well as names/assignments.
            if name.startswith("scripts/") and "moltenvk" in Path(name).name:
                pins.update(re.findall(SEMVER, line))
            for pin in sorted(pins - variants):
                errors.append(f"{name}:{number}: MoltenVK pin {pin} outside canonical variants")
            if (name.endswith(".md") or name.startswith("examples/")) and re.match(
                    r"\s*(?:export\s+)?CYDER_ENGINE_VERSION_LABEL=", line):
                if '"$(head -n 1 config/engine-version.txt)"' not in line:
                    errors.append(f"{name}:{number}: example label must read canonical config")

    for name in (README, GUIDE, WORKFLOW):
        if label not in corpus[name]:
            errors.append(f"{name}: missing canonical release label {label}")
    for name in (README, GUIDE, WORKFLOW, INTEGRATION, INCREMENTAL, "patches/README.md",
                 PACKER, INSTALLER):
        # Set equality detects both obsolete variants and silently dropped reals.
        documented = set(LIBRARY.findall(corpus[name]))
        if documented != variants:
            errors.append(f"{name}: documented MoltenVK variants disagree with config")

    default = re.findall(r'MOLTENVK_VERSION="\$\{MOLTENVK_VERSION:-([^}]+)\}"', corpus[ENV])
    installed_default = re.findall(r'^DEFAULT_VARIANT="([^"]+)"$', corpus[INSTALLER], re.MULTILINE)
    if len(default) != 1 or default[0] not in variants:
        errors.append(f"{ENV}: default MoltenVK version disagrees with config")
    if installed_default != default:
        errors.append(f"{INSTALLER}: default variant disagrees with graphics build default")
    if 'head -n 1 "$OGOM/config/engine-version.txt"' not in corpus[PACKER]:
        errors.append(f"{PACKER}: default label must read canonical config")
    if 'export OGOM="$PWD"' not in corpus[RELEASE_SKILL]:
        errors.append(f"{RELEASE_SKILL}: release example must use engine repo config")
    return errors


def negative_regressions(corpus):
    """Mutate in-memory fixtures only; never edit the user's checkout."""
    contract = json.loads(corpus[CONFIG])
    label = contract["versionLabel"]
    variants = sorted(set(LIBRARY.findall(contract["notes"])))
    default = re.search(r'MOLTENVK_VERSION="\$\{MOLTENVK_VERSION:-([^}]+)\}"', corpus[ENV])[1]
    alternate = next(variant for variant in variants if variant != default)
    next_label = re.sub(r"Cyder(\d+)", lambda m: f"Cyder{int(m[1]) + 1:03d}", label)
    next_variant = default.rsplit(".", 1)[0] + "." + str(int(default.split(".")[-1]) + 1)
    while next_variant in variants:
        next_variant = next_variant.rsplit(".", 1)[0] + "." + str(int(next_variant.split(".")[-1]) + 1)
    count = 0

    def rejected(description, updates, expected):
        nonlocal count
        fixture = dict(corpus)
        fixture.update(updates)
        errors = audit(fixture)
        if not any(expected in error for error in errors):
            raise AssertionError(f"{description} should fail with {expected!r}; got {errors}")
        count += 1

    rejected("malformed config", {CONFIG: "{"}, "Invalid canonical contract")
    rejected("empty version file", {VERSION: ""}, "label disagrees")
    rejected("extra version-file label", {VERSION: label + "\n" + next_label + "\n"}, "label disagrees")
    rejected("config label mismatch", {VERSION: next_label + "\n"}, "label disagrees")
    changed = dict(contract, versionLabel=next_label)
    rejected("release bump without doc updates",
             {CONFIG: json.dumps(changed), VERSION: next_label + "\n"}, "engine pin")
    changed = dict(contract, notes=LIBRARY.sub("libMoltenVK.dylib", contract["notes"]))
    rejected("unparseable variant contract", {CONFIG: json.dumps(changed)}, "two distinct")
    changed = dict(contract, notes=contract["notes"].replace(
        f"libMoltenVK-{default}.dylib", f"libMoltenVK-{next_variant}.dylib"))
    rejected("variant bump without doc updates", {CONFIG: json.dumps(changed)}, "documented MoltenVK variants")
    rejected("wrong README variant", {README: corpus[README] + f"\nMoltenVK {next_variant}\n"}, "outside canonical variants")
    rejected("missing README fallback", {README: corpus[README].replace(
        f"libMoltenVK-{variants[0]}.dylib", "libMoltenVK.real.dylib")}, "documented MoltenVK variants")
    rejected("hardcoded pack example", {GUIDE: corpus[GUIDE] +
             f"\nCYDER_ENGINE_VERSION_LABEL='{label}' \\\n"}, "example label must read")
    rejected("new stale example", {"examples/release.sh":
             f"CYDER_ENGINE_VERSION_LABEL='{next_label}'\nMOLTENVK_VERSION={next_variant}\n"}, "engine pin")
    rejected("new stale JSON example", {"examples/graphics.json":
             json.dumps({"MoltenVK": next_variant})}, "outside canonical variants")
    rejected("hardcoded exported label", {"examples/release.sh":
             f"export CYDER_ENGINE_VERSION_LABEL='{label}'\n"}, "example label must read")
    rejected("new stale release doc", {"docs/new-release.md":
             f"Engine: {next_label}; MoltenVK {next_variant}\n"}, "outside canonical variants")
    rejected("graphics default drift", {ENV: corpus[ENV].replace(
        f"MOLTENVK_VERSION:-{default}", f"MOLTENVK_VERSION:-{next_variant}")}, "default MoltenVK version")
    rejected("installer default drift", {INSTALLER: corpus[INSTALLER].replace(
        f'DEFAULT_VARIANT="{default}"', f'DEFAULT_VARIANT="{alternate}"')}, "default variant disagrees")
    for name in (PACKER, INSTALLER):
        rejected("release script missing fallback real", {name: corpus[name].replace(
            f"libMoltenVK-{alternate}.dylib", "libMoltenVK.real.dylib")}, "documented MoltenVK variants")
    rejected("archive example drift", {GUIDE: corpus[GUIDE].replace(
        label.replace(".", "-"), next_label.replace(".", "-"))}, "engine pin")
    rejected("legacy exception copied into current docs", {README: corpus[README] +
             "\n" + next(iter(HISTORICAL_LINES[PACKER])) + "\n"}, "engine pin")
    worklog = next(iter(HISTORICAL_SECTIONS))
    rejected("new worklog target outside dated history", {worklog:
             f"Engine: {next_label}\n" + corpus[worklog]}, "engine pin")
    rejected("missing release entrypoint", {README: ""}, "missing canonical release label")
    fixture = dict(corpus)
    del fixture[CONFIG]
    if not any("Missing required file" in error for error in audit(fixture)):
        raise AssertionError("Missing config must fail closed")
    return count + 1


def main():
    try:
        corpus = read_corpus()
        errors = audit(corpus)
        if errors:
            print("FAIL release contract:\n" + "\n".join(errors), file=sys.stderr)
            return 1
        count = negative_regressions(corpus)
    except (OSError, UnicodeError, AssertionError) as exc:
        print(f"FAIL release contract: {exc}", file=sys.stderr)
        return 1
    print(f"PASS release contract: canonical config/docs/examples agree; {count} drift cases rejected")
    return 0


if __name__ == "__main__":
    sys.exit(main())

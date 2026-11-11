#!/usr/bin/env python3
"""Compare relocated engine GStreamer discovery without starting Wine or a game.

Usage: python3 probe-media.py --engine /path/to/engine --output /tmp/uma-probe
Only the output directory is written; both cases use a new private registry.
Factory discovery does not prove a particular movie can be decoded.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    engine = args.engine.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    library = engine / "lib/wine/x86_64-unix/libgstreamer-1.0.0.dylib"
    plugins = engine / "lib/wine/gstreamer-1.0"
    scanner = engine / "libexec/gstreamer-1.0/gst-plugin-scanner"
    for path in (library, plugins, scanner):
        if not path.exists():
            parser.error(f"missing engine component: {path}")
    binary = output / "gst-probe"
    subprocess.run(["/usr/bin/clang", "-arch", "x86_64",
                    "-mmacosx-version-min=10.15", str(Path(__file__).with_name("gst-probe.c")),
                    "-o", str(binary)], check=True)
    results = {}
    for case in ("baseline_fresh_registry", "explicit_paths_fresh_registry"):
        env = {k: v for k, v in os.environ.items() if not k.startswith("GST_")}
        registry = output / (case + ".bin")
        # Remove only this probe's own cache when rerunning the same output folder.
        registry.unlink(missing_ok=True)
        env["GST_REGISTRY_1_0"] = str(registry)
        env["DYLD_FALLBACK_LIBRARY_PATH"] = f"{engine}/lib:{library.parent}"
        if case.startswith("explicit"):
            env.update(GST_PLUGIN_SYSTEM_PATH_1_0=str(plugins),
                       GST_PLUGIN_PATH_1_0=str(plugins), GST_PLUGIN_SCANNER=str(scanner))
        completed = subprocess.run(["/usr/bin/arch", "-x86_64", str(binary), str(library)],
                                   env=env, capture_output=True, text=True, timeout=90)
        (output / (case + ".stderr.txt")).write_text(completed.stderr)
        results[case] = {"returncode": completed.returncode,
                         "factories": dict(line.split("=", 1) for line in completed.stdout.splitlines()
                                           if "=" in line)}
        if completed.returncode:
            raise RuntimeError(f"{case} failed; inspect its stderr file")
    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()

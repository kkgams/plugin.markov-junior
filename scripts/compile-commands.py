"""Emit clangd commands from Make flags and the pinned compiler environment."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--entry", nargs=4, action="append", required=True,
                    metavar=("TARGET", "COMPILER", "FLAGS", "SOURCES"))
args = parser.parse_args()
commands = []
for target, compiler, flags, sources in args.entry:
    driver = shlex.split(compiler)
    driver[0] = shutil.which(driver[0]) or driver[0]
    if not Path(driver[0]).is_file():
        raise FileNotFoundError(driver[0])
    if target == "wasi":
        sysroot = Path(os.environ["WASI_SYSROOT"])
        if not sysroot.is_dir():
            raise FileNotFoundError(sysroot)
        platform = ["--target=wasm32-wasip2", f"--sysroot={sysroot}"]
    else:
        raise ValueError(f"Unknown target: {target}")
    for source in shlex.split(sources):
        commands.append({"directory": str(Path.cwd()), "file": source,
                         "arguments": [*driver, *platform, *shlex.split(flags), "-c", source]})
json.dump(commands, sys.stdout, indent=2)
print()

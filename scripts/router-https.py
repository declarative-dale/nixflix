#!/usr/bin/env python3
"""Prepare disabled OPNsense Caddy routes for router-managed public certificates.

Run on the workstation after installing os-caddy. No credential is accepted or
printed. A subsequent activation requires a DNS token entered in the router UI.
"""

import argparse
import base64
import json
from pathlib import Path
import shlex
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["plan", "prepare"])
    parser.add_argument("--router", default="root@10.42.0.1")
    parser.add_argument("--control-path")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    manifest = json.loads((root / "hosts/nixflix/local-services.json").read_text())
    code = (root / "scripts/router-https.php").read_text().removeprefix("<?php")
    command = [
        "/usr/local/bin/php",
        "-r",
        "eval(base64_decode('" + base64.b64encode(code.encode()).decode() + "'));",
    ]
    ssh = ["ssh", "-F", "/dev/null", "-o", "BatchMode=yes"]
    if args.control_path:
        ssh += ["-o", "ControlPath=" + args.control_path]
    result = subprocess.run(
        ssh + [args.router, shlex.join(command)],
        input=json.dumps({"action": args.action, "manifest": manifest}),
        text=True,
        check=False,
    )
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()

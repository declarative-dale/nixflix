#!/usr/bin/env python3
"""Build and activate an exact committed revision from the personal fork."""

import argparse
import os
import re
import shlex
import subprocess

REMOTE = "marty@10.69.0.18"
SSH = [
    "ssh",
    "-F",
    os.environ.get("NIXFLIX_SSH_CONFIG", "/dev/null"),
    "-o",
    "BatchMode=yes",
]
REPOSITORY = "git+https://github.com/declarative-dale/nixflix"


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("action", choices=["build", "test", "switch", "rollback"])
    p.add_argument("revision", help="Jujutsu revision, normally migration/nixflix")
    a = p.parse_args()
    commit = subprocess.check_output(
        ["jj", "log", "--no-graph", "-r", a.revision, "-T", "commit_id"], text=True
    ).strip()
    if not re.fullmatch("[0-9a-f]{40}", commit):
        p.error("revision must resolve to exactly one Git commit")
    flake = f"{REPOSITORY}?rev={commit}"
    result = "/var/lib/nixflix-deploy/" + commit
    script = f"""
set -eu
sudo -n install -d -m 755 /var/lib/nixflix-deploy
sudo -n nix build --no-write-lock-file --out-link {result} {shlex.quote(flake + '#nixosConfigurations.nixflix.config.system.build.toplevel')}
"""
    if a.action == "test":
        script += f"""
sudo -n {result}/bin/switch-to-configuration test
sudo -n sh -c 'printf "%s\\n" {commit} > /var/lib/nixflix-deploy/tested'
"""
    elif a.action in ("switch", "rollback"):
        script += f"""
test "$(cat /var/lib/nixflix-deploy/tested)" = {commit}
sudo -n nix-env --profile /nix/var/nix/profiles/system --set {result}
sudo -n {result}/bin/switch-to-configuration switch
sudo -n sh -c 'printf "%s\\n" {commit} > /var/lib/nixflix-deploy/deployed'
sudo -n tee /etc/nixos/flake.nix >/dev/null <<'FLAKE'
{{
  description = "nixflix deployment entry point; edit the personal repository";
  inputs.managed.url = "{flake}";
  outputs = {{ managed, ... }}: {{ inherit (managed) nixosConfigurations; }};
}}
FLAKE
sudo -n nix flake lock /etc/nixos
"""
    subprocess.run(SSH + [REMOTE, script], check=True)
    if a.action in ("test", "switch", "rollback"):
        subprocess.run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                REMOTE,
                'sudo -n true && test "$(hostname)" = nixflix && systemctl is-active xen-guest-agent',
            ],
            check=True,
        )
    print(f"{a.action}: {commit}")


if __name__ == "__main__":
    main()

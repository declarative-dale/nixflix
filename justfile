# All recipes run in the pinned environment: nix develop -c just <recipe>
set shell := ["bash", "-euo", "pipefail", "-c"]

check:
    python3 -m unittest discover -s tests/migration -v
    nix eval .#nixosConfigurations.nixflix.config.system.build.toplevel.drvPath
    nix build .#checks.x86_64-linux.four-instance-eval
    treefmt --fail-on-change

build revision="migration/nixflix":
    python3 scripts/deploy.py build '{{revision}}'

test revision="migration/nixflix":
    python3 scripts/deploy.py test '{{revision}}'

switch revision="migration/nixflix":
    python3 scripts/deploy.py switch '{{revision}}'

# Test the selected old revision before making it the boot default.
rollback revision:
    python3 scripts/deploy.py test '{{revision}}'
    python3 scripts/deploy.py rollback '{{revision}}'

# Run on .18 as marty from a checkout of this repository.
provision:
    secretspec run --provider pass -- python3 scripts/provision-secrets.py emit | sudo -n python3 scripts/provision-secrets.py install

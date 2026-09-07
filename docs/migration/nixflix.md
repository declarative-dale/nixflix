# nixflix migration and operations

The personal fork `declarative-dale/nixflix` manages `marty@10.69.0.18`.
`kiriwalawren/nixflix` is an upstream remote. A push never deploys the VM.
The host uses locked NixOS 26.05; the project's original unstable input is retained.

## Repository workflow

```sh
nix develop
jj status
jj new migration/nixflix
# Edit and check; jj snapshots new files automatically.
just check
jj commit -m 'Describe the resulting change'
jj bookmark set migration/nixflix -r @-
jj git push --remote origin --bookmark migration/nixflix
just build migration/nixflix
just test migration/nixflix
just switch migration/nixflix
```

The deployment command resolves one Git commit with jj and builds that exact
revision from the personal fork on the target. `test` must succeed before `switch`.
A new SSH connection checks sudo, hostname, and the Xen guest agent. The deployed
commit is recorded in `/var/lib/nixflix-deploy/deployed`. `/etc/nixos/flake.nix`
points to that exact revision. Edit this repository for further system changes.

For upstream changes, run `jj git fetch --remote upstream`, inspect
`jj log -r 'main@origin..main@upstream'`, and deliberately merge/rebase the desired
commits into the migration bookmark. Run checks before pushing to `origin`.
Never deploy upstream directly. `just rollback COMMIT` tests and switches to a
selected older committed configuration. Existing system generations are also
available in the EFI boot menu. System rollback does not undo database migrations;
restore a compatible protected snapshot as well.

## Isolation and service state

Every staged media process uses the `nixflix-staging` network namespace. It has
only loopback, no physical interface, default route, or internet access. The NAS
is mounted read-only at `/data`. Native Plex sees `/data/media` at `/media`.
Stash retains `/data`, `/generated`, `/metadata`, `/cache`, and `/root/.stash`.
No media ports are exposed on the LAN. Inspect services through
`sudo ip netns exec nixflix-staging COMMAND` on .18.

Services require a real CIFS mount, stop when it disappears, and require a
root-owned `/var/lib/nixflix-migration/ready/UNIT` marker before they start.
They are initially manual-start because copied configurations contain live
production identities and schedules and the VM has only 4 GiB RAM. Do not remove
namespace or read-only protections to work around staging errors. The staging
slice is limited to 3200 MiB so load testing cannot consume all host memory.

Automatic Arr reconciliation is disabled on this host to preserve restored
roots, monitored status, history and paths. The reusable modules still integrate
all four instances with Prowlarr, download clients, SAB categories and Recyclarr.
Profiles must exist before running `scripts/reassign-profiles.py` inside the
namespace as root. It updates only qualityProfileId, requests no file moves,
checks paths/monitored status after all updates, then deletes obsolete profiles.

| Source | Target | Port | Managed profile |
| --- | --- | --- | --- |
| sonarr2 | sonarr | 8990 | WEB-1080p (Alternative) |
| sonarr | sonarr-4k | 8989 | WEB-2160p (Alternative) |
| radarr2 | radarr | 7879 | [SQP] SQP-1 (1080p) |
| radarr | radarr-4k | 7878 | [SQP] SQP-1 (2160p) |

Two Bazarr instances remain necessary for the separate Sonarr/Radarr pairs;
ports are 6767 and 6777. Native Seerr is independent of the Jellyfin-oriented
nixflix module. Its first startup migrates a **copy** of Overseerr state, per
[Seerr's migration guide](https://docs.seerr.dev/migration-guide/). Plex uses the
public package and preserved preferences/identity; Plex Pass is account-bound.
A cloned identity must remain isolated until the final cutover.

## Secrets

SecretSpec declares required credentials in `secretspec.toml`. Following the
[pass provider convention](https://secretspec.dev/providers/pass/), entries are
`secretspec/nixflix/default/NAME`. `scripts/extract-source-secrets.py` runs as root
on Ubuntu and streams its output directly to `scripts/import-pass.py` on .18.
No private SSH key is transferred. The target has a locally generated GPG identity;
its bootstrap key has no passphrase and is protected by the marty account's file
permissions. Add a passphrase/re-encrypt to your preferred key when convenient.
Runtime services never invoke GPG or pass.

From a checkout on .18, use `nix develop -c just provision`. It resolves through
pass, then atomically installs a generation under `/var/lib/nixflix-secrets`.
Root owns the directory (0700) and files (0600). The `current` symlink is switched
only after all required values validate. Arr uses systemd `LoadCredential` for
private runtime copies. Repeating provisioning with unchanged values is a no-op.
To rotate, use `secretspec set NAME --provider pass`, provision, and restart the
consumer. Remount `/data` for SMB credential changes. Older credential generations
remain root-only for deliberate rollback and may be removed after validation.
Other provider credentials and application tokens remain in the protected copied
application configuration; enter replacements through pass rather than Nix literals.

## Backups and cutover

Protected snapshots live under `/var/lib/nixflix-migration` on both hosts, outside
the repository. `scripts/snapshot.py` uses SQLite's backup API for live databases,
records timestamps, and copies Plex's latest dated library backups. Plex metadata
and preferences are copied while production runs: this is a staging snapshot,
not a final consistent cutover backup. SAB's queue and non-SQLite settings are
also provisional. Archive Ombi and Wizarr; leave unrelated Ubuntu services alone.

Before later cutover, take final consistent snapshots with source writers stopped,
verify restored counts/history and service destinations, and explicitly plan
routing changes. Do not bulk-search, rename, move media, or enable library-wide
upgrades. Assess concurrent memory pressure first. GPU passthrough and its
hypervisor configuration remain separate work; validate Intel VA-API and Plex /
Stash hardware transcoding only after a render device is present.

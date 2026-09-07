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
Validated restored services start through `nixflix-staging.target` after reboot.
The readiness markers and namespace remain mandatory because copied configurations
contain live production identities and schedules and the VM has only 4 GiB RAM. Do not remove
namespace or read-only protections to work around staging errors. The staging
slice is limited to 3200 MiB so load testing cannot consume all host memory.

Automatic Arr reconciliation is disabled on this host to preserve restored
roots, monitored status, history and paths. The reusable modules still integrate
all four instances with Prowlarr, download clients, SAB categories and Recyclarr.
Profiles must exist before running `scripts/reassign-profiles.py` inside the
namespace as root. It updates only qualityProfileId, requests no file moves,
checks paths/monitored status after all updates, updates import-list and Radarr
collection profile references, then deletes obsolete profiles. Individual collection
updates avoid the bulk endpoint that would enqueue a collection refresh.

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

## Verified preparation, 2026-09-07

The root partition now starts at the original sector 2101248 and has size
260042719 sectors. ext4 reports 122 GiB. Filesystem UUIDs, EFI, NetworkManager,
stateVersion and the existing `xen-guest-agent` service were retained. Partition
backups and the original `/etc/nixos` configuration are in
`/var/lib/nixflix-migration/bootstrap` on .18.

The source and target each hold `snapshot-2026-09-07` (approximately 16 GiB).
Plex's library and blobs databases use dated 2026-09-07 backups. All state is on
local ext4; the NAS supplies only read-only media during staging. The live Ubuntu
services were not stopped. drbrown has the explicitly approved passwordless sudo
rule `/etc/sudoers.d/nixflix-migration`. marty is the target administrator; the
nixos account was removed after a separate key-authenticated sudo session passed.

Verified restored Arr counts, paths, monitored flags and history:

| Instance | Titles / artists | History rows |
| --- | ---: | ---: |
| Sonarr HD | 195 | 21435 |
| Sonarr 4K | 70 | 7801 |
| Radarr HD | 402 | 833 |
| Radarr 4K | 166 | 411 |
| Lidarr | 4 | 489 |

All four managed profiles were synced from the locked TRaSH resources, titles and
remaining profile references reassigned, and obsolete profiles removed. Prowlarr
applications and Arr SAB clients point to the local isolated endpoints. SAB retains
copied settings and queue state, adding the four managed categories plus Lidarr.
Seerr retains 4 users, 662 media records and 354 requests, with all four destinations
pointing at the new profile IDs. Its database and Audiobookshelf's database passed
SQLite quick_check. Plex retained its machine identifiers and token, and returned
five authenticated library sections using the original `/media` paths. Its cloud
subscription endpoint is inaccessible in isolation; live entitlement and hardware
transcoding validation remain for cutover/GPU work.

All 18 HTTP ports responded during staging (Plex requires authentication).
Concurrent startup and library/API checks used about 2.7 GiB in the staging slice;
its memory-high threshold was reached, with zero OOM kills observed. This is limited
headroom for heavy scans or transcoding: the current 4 GiB allocation should not be
considered production capacity validation. Hypervisor assignments were unchanged.

`test-isolation.py` verified missing API credentials prevent startup and NAS loss
stops all media units without local fallback writes, then restored the services.
Repeated SecretSpec provisioning kept the same generation. The reusable Arr helper
now explicitly checks credentials before starting, fixing a fallback-to-empty-key
behavior found by this test. Recyclarr state/configuration permissions are 0700/0600.

Useful operations on .18:

```sh
sudo systemctl status nixflix-staging.target
sudo ip netns exec nixflix-staging curl http://127.0.0.1:5055/api/v1/status
sudo python3 scripts/validate-state.py /var/lib/nixflix-migration/snapshot-2026-09-07
# Temporarily interrupts ONLY staged services and restores them:
sudo python3 scripts/test-isolation.py
```

To inspect a staged UI from the workstation without allowing outbound traffic,
run a localhost-only relay on .18, then an SSH tunnel from the workstation:

```sh
# On .18, for Seerr:
sudo socat TCP-LISTEN:15055,bind=127.0.0.1,reuseaddr,fork EXEC:'ip netns exec nixflix-staging socat STDIO TCP:127.0.0.1:5055'
# On the workstation, in another terminal:
ssh -F /dev/null -L 15055:127.0.0.1:15055 marty@10.69.0.18
```

Browse `http://localhost:15055`; stop the relay when finished. Plex cloud sign-in
and external notifications/downloads are intentionally unavailable in isolation.
For later GPU validation set `nixflixHost.gpuPassthrough.enable = true` only after
passthrough exists, then test VA-API and real Plex/Stash transcoding. Production
cutover still requires a final consistent transfer, tested cloud authentication,
provider credentials, deliberate routing changes, and a memory/concurrency decision.


## RAM, GPU, notifications and proxy preparation

The VM now has 16 GiB RAM and Intel UHD 750 (`8086:4c8a`) passthrough.
The staging slice allows 10 GiB before throttling and 12 GiB maximum, retaining
headroom for the OS and Nix builds. Plex receives the render device. Stash uses
the host's pinned FFmpeg and Intel driver through read-only store/driver mounts;
the preserved Alpine image does not include the Intel userspace driver.

A NAS recovery timer retries a failed boot mount every minute and starts ready
staging services when connectivity returns. Stop `nixflix-nas-recover.timer` and
its service before intentionally unmounting the NAS for maintenance.

Notifiarr is removed from the target service definitions; its snapshots and
application state remain available. Apprise API is pinned by digest and prepared
for Discord plus Matrix. It has no published container port or proxy route.
Upstream Notif covers HD/4K Sonarr and Radarr plus Lidarr, preserves unmanaged
connections during migration, and resolves arbitrary secret fields at runtime.
Its configuration jobs are manual during staging.

Provision on `.18` as marty, using hidden pass input (values never enter shell
history):

```sh
pass insert secretspec/nixflix/notifications/DISCORD_APPRISE_URL
pass insert secretspec/nixflix/notifications/MATRIX_APPRISE_URL
nix develop -c just provision-notifications
```

The values are Apprise destination URLs: `discord://WEBHOOK_ID/WEBHOOK_TOKEN`
and `matrixs://ACCESS_TOKEN@HOMESERVER/!ROOM_ID` (URL-encode credentials where
required). The installer requires both, writes an atomic root-owned mode-0600
JSON/YAML configuration outside the Nix store, and is safe to repeat. Runtime
copies are mode 0400 and readable only by the dedicated Apprise user.
Provisioning alone does not start delivery. A ready marker and explicit testing
are required before activating Apprise and the Arr notification jobs.

Seerr's managed pre-start prepares an Apprise webhook for request/approval,
availability and issue events, disabled during staging. It preserves a local
backup of the old settings. Approval messages link to authenticated Seerr at
`https://seeme.dalebox.pw/requests`; there is no unauthenticated approval endpoint
or embedded API key. At production activation, enable this webhook deliberately
and remove the staging pre-start's forced disabled setting.

Caddy uses upstream's virtual-host helpers inside the loopback-only namespace.
The existing `seeme.dalebox.pw` request hostname is preserved. Other generated
service subdomains under `dalebox.pw` are prepared routes, not published DNS.
The current Cloudflare tunnel terminates HTTPS; the staged Caddy origin uses
HTTP. Existing `.12` tunnel routes are unchanged. Keep Apprise's API private
when production networking is implemented. `notify.816913.xyz` still routes to
source Notifiarr and should be retired deliberately at cutover; Matrix and
other unrelated tunnel routes must remain intact.

#!/usr/bin/env python3
"""Rewire copied integrations inside the staging namespace; never submit searches."""

import json
import os
from pathlib import Path
import subprocess
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

INSTANCES = {
    "sonarr": (8990, "WEB-1080p (Alternative)"),
    "sonarr-4k": (8989, "WEB-2160p (Alternative)"),
    "radarr": (7879, "[SQP] SQP-1 (1080p)"),
    "radarr-4k": (7878, "[SQP] SQP-1 (2160p)"),
    "lidarr": (8686, None),
}


def api(port, key, method, path, value=None, version="v3"):
    if port == 8686:
        version = "v1"
    req = Request(
        f"http://127.0.0.1:{port}/api/{version}/{path}",
        headers={"X-Api-Key": key, "Content-Type": "application/json"},
        data=json.dumps(value).encode() if value is not None else None,
        method=method,
    )
    with urlopen(req, timeout=60) as response:
        body = response.read()
        return json.loads(body) if body else None


def secret(name):
    return Path("/var/lib/nixflix-secrets/current", name).read_text().strip()


def main():
    os.umask(0o077)
    prowlarr_key = secret("prowlarr")
    for app in api(9696, prowlarr_key, "GET", "applications", version="v1"):
        fields = {f["name"]: f for f in app["fields"]}
        port = urlsplit(fields["baseUrl"]["value"]).port
        if port not in (8990, 8989, 7879, 7878, 8686, 8787, 6969):
            continue
        fields["baseUrl"]["value"] = f"http://127.0.0.1:{port}"
        fields["prowlarrUrl"]["value"] = "http://127.0.0.1:9696"
        api(
            9696,
            prowlarr_key,
            "PUT",
            f"applications/{app['id']}?forceSave=true",
            app,
            version="v1",
        )
    for name, (port, _) in INSTANCES.items():
        key = secret(name)
        for client in api(port, key, "GET", "downloadclient"):
            if client["implementation"] != "Sabnzbd":
                continue
            fields = {f["name"]: f for f in client["fields"]}
            for field, value in {
                "host": "127.0.0.1",
                "port": 8080,
                "apiKey": secret("sabnzbd"),
            }.items():
                fields[field]["value"] = value
            for field in ("tvCategory", "movieCategory", "musicCategory"):
                if field in fields:
                    fields[field]["value"] = name
            api(
                port,
                key,
                "PUT",
                f"downloadclient/{client['id']}?forceSave=true",
                client,
            )
    # Stop the writer before editing copied Seerr settings, then atomically replace.
    subprocess.run(["systemctl", "stop", "seerr"], check=True)
    file = Path("/var/lib/seerr/settings.json")
    settings = json.loads(file.read_text())
    for app in ("sonarr", "radarr"):
        for destination in settings.get(app, []):
            name = app + ("-4k" if destination.get("is4k") else "")
            port, profile = INSTANCES[name]
            key = secret(name)
            matches = [
                p
                for p in api(port, key, "GET", "qualityprofile")
                if p["name"] == profile
            ]
            if len(matches) != 1:
                raise RuntimeError("Managed profile is missing")
            destination.update(
                hostname="127.0.0.1",
                port=port,
                apiKey=key,
                activeProfileId=matches[0]["id"],
                activeProfileName=profile,
            )
    pending = file.with_suffix(".pending")
    pending.write_text(json.dumps(settings, indent=2) + "\n")
    os.chown(pending, file.stat().st_uid, file.stat().st_gid)
    os.replace(pending, file)
    subprocess.run(["systemctl", "start", "seerr"], check=True)
    print("Configured Prowlarr, SABnzbd clients, and all four Seerr destinations.")


if __name__ == "__main__":
    main()

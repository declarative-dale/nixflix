#!/usr/bin/env python3
"""Assign an instance's titles to one existing profile, verify, then remove obsolete profiles.
Never submits commands, searches, renames or moveFiles requests.
"""

import argparse
import json
from pathlib import Path
import sys
from urllib.request import Request, urlopen

PROFILES = {
    "sonarr": (8990, "series", "WEB-1080p (Alternative)"),
    "sonarr-4k": (8989, "series", "WEB-2160p (Alternative)"),
    "radarr": (7879, "movie", "[SQP] SQP-1 (1080p)"),
    "radarr-4k": (7878, "movie", "[SQP] SQP-1 (2160p)"),
}


def migrate(call, endpoint, desired):
    profiles = call("GET", "qualityprofile")
    matches = [p for p in profiles if p["name"] == desired]
    if len(matches) != 1:
        raise ValueError("The exact managed profile must exist before reassignment")
    target = matches[0]["id"]
    titles = call("GET", endpoint)
    before = {t["id"]: (t.get("path"), t.get("monitored")) for t in titles}
    for title in titles:
        if title["qualityProfileId"] != target:
            updated = dict(title, qualityProfileId=target)
            call("PUT", f"{endpoint}/{title['id']}?moveFiles=false", updated)
    after = call("GET", endpoint)
    if before != {t["id"]: (t.get("path"), t.get("monitored")) for t in after} or any(
        t["qualityProfileId"] != target for t in after
    ):
        raise ValueError("Verification failed; no obsolete profiles were deleted")
    for profile in profiles:
        if profile["id"] != target:
            call("DELETE", f"qualityprofile/{profile['id']}")
    return len(after)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("instance", choices=PROFILES)
    args = p.parse_args()
    port, endpoint, profile = PROFILES[args.instance]
    key = Path("/var/lib/nixflix-secrets/current", args.instance).read_text().strip()

    def call(method, resource, payload=None):
        request = Request(
            f"http://127.0.0.1:{port}/api/v3/{resource}",
            data=json.dumps(payload).encode() if payload is not None else None,
            headers={"X-Api-Key": key, "Content-Type": "application/json"},
            method=method,
        )
        with urlopen(request, timeout=60) as response:
            data = response.read()
            return json.loads(data) if data else None

    try:
        count = migrate(call, endpoint, profile)
    except Exception:
        sys.exit(
            "Profile migration failed; inspect the instance before retrying. No searches or moves were requested."
        )
    print(f"{args.instance}: verified {count} titles on {profile}")


if __name__ == "__main__":
    main()

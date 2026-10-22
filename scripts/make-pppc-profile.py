#!/usr/bin/env python3
"""Writes a configuration profile that pre-approves DockFlip's Accessibility
permission, for Macs managed with an MDM (Jamf, Intune, Kandji, Mosyle…).

    python3 scripts/make-pppc-profile.py /Applications/DockFlip.app DockFlip-Accessibility.mobileconfig

The profile pins DockFlip's code signature, so it only applies to the real,
release-signed DockFlip. It takes effect only when delivered by an MDM;
double-clicking it on a Mac does not grant anything.
"""
import plistlib
import subprocess
import sys
import uuid

BUNDLE_ID = "io.github.dockflip.DockFlip"
NAMESPACE = uuid.UUID("6f6b2b8e-0d0f-4d55-9d36-6b0c8f1f7a21")


def designated_requirement(app: str) -> str:
    out = subprocess.run(
        ["codesign", "--display", "--requirements", "-", app],
        capture_output=True, text=True, check=True,
    ).stdout
    for line in out.splitlines():
        if line.startswith("designated => "):
            return line[len("designated => "):].strip()
    sys.exit(f"error: no designated requirement in {app}")


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    app, out = sys.argv[1], sys.argv[2]
    requirement = designated_requirement(app)
    # Stable UUIDs: uploading a newer profile replaces the old one in the MDM.
    profile = {
        "PayloadType": "Configuration",
        "PayloadVersion": 1,
        "PayloadIdentifier": f"{BUNDLE_ID}.pppc",
        "PayloadUUID": str(uuid.uuid5(NAMESPACE, "profile")).upper(),
        "PayloadDisplayName": "DockFlip: allow Accessibility",
        "PayloadDescription": "Lets DockFlip list, switch and snap windows without asking the user.",
        "PayloadOrganization": "DockFlip",
        "PayloadScope": "System",
        "PayloadContent": [{
            "PayloadType": "com.apple.TCC.configuration-profile-policy",
            "PayloadVersion": 1,
            "PayloadIdentifier": f"{BUNDLE_ID}.pppc.tcc",
            "PayloadUUID": str(uuid.uuid5(NAMESPACE, "tcc")).upper(),
            "PayloadDisplayName": "DockFlip Accessibility",
            "Services": {
                "Accessibility": [{
                    "Identifier": BUNDLE_ID,
                    "IdentifierType": "bundleID",
                    "CodeRequirement": requirement,
                    "StaticCode": False,
                    "Allowed": True,
                    "Comment": "Window lists, the ⌘Tab switcher and snapping.",
                }],
            },
        }],
    }
    with open(out, "wb") as f:
        plistlib.dump(profile, f)
    print(f"Wrote {out}\n  CodeRequirement: {requirement}")


if __name__ == "__main__":
    main()

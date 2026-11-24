#!/usr/bin/env python3
"""Publish only complete, verified drafts and preserve existing public assets."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def asset_names(version):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Expected a numeric major.minor.patch version.")
    stem = f"HA-Sensor-Bar-{version}-arm64"
    return [f"{stem}.dmg", f"{stem}.zip", f"{stem}.sha256", "SHA256SUMS.txt"]


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def verify_assets(directory, version):
    names = asset_names(version)
    for name in names:
        path = directory / name
        if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
            raise ValueError(f"Missing or empty release asset: {name}")
    manifest = (directory / "SHA256SUMS.txt").read_bytes()
    if manifest != (directory / names[2]).read_bytes():
        raise ValueError("Checksum manifests disagree.")
    checksums = {}
    for line in manifest.decode("utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9.-]+)", line)
        if not match or match[2] in checksums:
            raise ValueError("Invalid or duplicate checksum entry.")
        checksums[match[2]] = match[1]
    if set(checksums) != set(names[:2]):
        raise ValueError("Checksum manifest must cover exactly the DMG and ZIP.")
    for name, expected in checksums.items():
        if digest(directory / name) != expected:
            raise ValueError(f"Checksum mismatch: {name}")
    return names


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


def release_metadata(repo, tag, command=run):
    try:
        return json.loads(command("gh", "api", f"repos/{repo}/releases/tags/{tag}"))
    except subprocess.CalledProcessError as error:
        if "(HTTP 404)" in (error.stderr or ""):
            return None
        raise


def verify_remote(repo, tag, version, metadata, command=run, expected_directory=None):
    names = asset_names(version)
    assets = {asset["name"]: asset for asset in metadata["assets"]}
    if any(name not in assets or assets[name]["size"] <= 0 or
           assets[name]["state"] != "uploaded" for name in names):
        raise ValueError("The release does not contain every completed asset.")
    with tempfile.TemporaryDirectory(prefix="ha-sensor-bar-release-") as temporary:
        directory = Path(temporary)
        patterns = [argument for name in names for argument in ("--pattern", name)]
        command("gh", "release", "download", tag, "--repo", repo, "--dir", temporary, *patterns)
        verify_assets(directory, version)
        for name in names:
            if (directory / name).stat().st_size != assets[name]["size"]:
                raise ValueError(f"Remote asset size mismatch: {name}")
            if expected_directory and digest(directory / name) != digest(expected_directory / name):
                raise ValueError(f"Uploaded asset differs from the build: {name}")


def publish(version, commit, repo, directory=Path("dist"), command=run):
    names = verify_assets(directory, version)
    tag = f"v{version}"
    # A manual dispatch must never reuse a version from a different commit.
    try:
        tagged_commit = command("git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}").strip()
    except subprocess.CalledProcessError:
        tagged_commit = None
    if tagged_commit and tagged_commit != commit:
        raise ValueError("The version tag points to a different commit.")
    metadata = release_metadata(repo, tag, command)
    if metadata and not metadata["draft"]:
        verify_remote(repo, tag, version, metadata, command)
        print(f"{tag} is already complete and public; existing assets were preserved.")
        return
    if metadata is None:
        command("gh", "release", "create", tag, "--repo", repo, "--draft",
                "--target", commit, "--title", f"HA Sensor Bar {version}",
                "--notes-file", "docs/RELEASE_NOTES.md")
    else:
        command("gh", "release", "edit", tag, "--repo", repo, "--draft=true",
                "--target", commit, "--title", f"HA Sensor Bar {version}",
                "--notes-file", "docs/RELEASE_NOTES.md")
    # Replacement is confined to a draft. A failed upload leaves it unpublished.
    command("gh", "release", "upload", tag, "--repo", repo,
            *(str(directory / name) for name in names), "--clobber")
    metadata = release_metadata(repo, tag, command)
    if not metadata or not metadata["draft"]:
        raise ValueError("Expected an unpublished draft before asset verification.")
    verify_remote(repo, tag, version, metadata, command, expected_directory=directory)
    command("gh", "release", "edit", tag, "--repo", repo, "--draft=false")
    print(f"Published {tag} after downloading and verifying all release assets.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--commit", required=True)
    parser.add_argument("--repo", required=True)
    arguments = parser.parse_args()
    publish(arguments.version, arguments.commit, arguments.repo)

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


def run(*args, output=None):
    if output is not None:
        with output.open("wb") as destination:
            subprocess.run(args, check=True, stdout=destination, stderr=subprocess.PIPE)
        return ""
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


def release_metadata(repo, tag, command=run):
    try:
        return json.loads(command("gh", "api", f"repos/{repo}/releases/tags/{tag}"))
    except subprocess.CalledProcessError as error:
        if "(HTTP 404)" in (error.stderr or ""):
            return None
        raise


def find_release(repo, tag, command=run):
    published = release_metadata(repo, tag, command)
    if published is not None:
        return published
    page = 1
    while True:
        releases = json.loads(command("gh", "api", f"repos/{repo}/releases?per_page=100&page={page}"))
        for release in releases:
            if release["tag_name"] == tag:
                return release
        if len(releases) < 100:
            return None
        page += 1


def get_release(repo, release_id, tag, command=run):
    metadata = json.loads(command("gh", "api", f"repos/{repo}/releases/{release_id}"))
    if metadata["id"] != release_id or metadata["tag_name"] != tag:
        raise ValueError("The release identity changed.")
    return metadata


def verify_remote(repo, version, metadata, command=run, expected_directory=None):
    names = asset_names(version)
    assets = {asset["name"]: asset for asset in metadata["assets"]}
    if any(name not in assets or assets[name]["size"] <= 0 or
           assets[name]["state"] != "uploaded" for name in names):
        raise ValueError("The release does not contain every completed asset.")
    with tempfile.TemporaryDirectory(prefix="ha-sensor-bar-release-") as temporary:
        directory = Path(temporary)
        for name in names:
            command("gh", "api", f"repos/{repo}/releases/assets/{assets[name]['id']}",
                    "--header", "Accept: application/octet-stream", output=directory / name)
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
    metadata = find_release(repo, tag, command)
    if metadata and not metadata["draft"]:
        metadata = get_release(repo, metadata["id"], tag, command)
        verify_remote(repo, version, metadata, command)
        print(f"{tag} is already complete and public; existing assets were preserved.")
        return
    # GitHub can replace a draft's tag with an untagged-* placeholder when a
    # metadata update omits tag_name. Carry it through every release mutation.
    fields = ("--raw-field", f"tag_name={tag}",
              "--raw-field", f"target_commitish={commit}",
              "--raw-field", f"name=HA Sensor Bar {version}",
              "--field", "body=@docs/RELEASE_NOTES.md")
    if metadata is None:
        metadata = json.loads(command("gh", "api", f"repos/{repo}/releases", "--method", "POST",
                                      "--field", "draft=true", *fields))
    release_id = metadata["id"]
    endpoint = f"repos/{repo}/releases/{release_id}"
    metadata = get_release(repo, release_id, tag, command)
    if not metadata["draft"]:
        raise ValueError("Expected an unpublished draft before asset upload.")
    command("gh", "api", endpoint, "--method", "PATCH", *fields)
    # Replacement is confined to a draft. A failed upload leaves it unpublished.
    for asset in metadata["assets"]:
        if asset["name"] in names:
            command("gh", "api", f"repos/{repo}/releases/assets/{asset['id']}", "--method", "DELETE")
    for name in names:
        command("gh", "api", f"https://uploads.github.com/{endpoint}/assets?name={name}",
                "--method", "POST", "--header", "Content-Type: application/octet-stream",
                "--input", str(directory / name))
    metadata = get_release(repo, release_id, tag, command)
    if not metadata["draft"]:
        raise ValueError("Expected an unpublished draft before asset verification.")
    verify_remote(repo, version, metadata, command, expected_directory=directory)
    command("gh", "api", endpoint, "--method", "PATCH",
            "--raw-field", f"tag_name={tag}", "--field", "draft=false")
    metadata = get_release(repo, release_id, tag, command)
    if metadata["draft"]:
        raise ValueError("The verified release is still a draft.")
    print(f"Published {tag} after downloading and verifying all release assets.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--commit", required=True)
    parser.add_argument("--repo", required=True)
    arguments = parser.parse_args()
    publish(arguments.version, arguments.commit, arguments.repo)

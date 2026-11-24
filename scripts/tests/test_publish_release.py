import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import parse_qs, urlparse

SPEC = importlib.util.spec_from_file_location("publisher", Path(__file__).parents[1] / "publish-release.py")
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)


class FakeGitHub:
    def __init__(self):
        self.metadata = None
        self.remote = {}
        self.calls = []
        self.fail_upload = False
        self.corrupt_download = False
        self.tag_commit = "example-commit"
        self.api_error = None
        self.api_error_endpoint = None
        self.other_releases = []
        self.publish_during_upload = False

    def seed_release(self, draft=True):
        self.metadata = {"id": 42, "tag_name": "v1.0.0", "draft": draft, "assets": []}

    @property
    def mutations(self):
        return [call for call in self.calls if "--method" in call
                and call[call.index("--method") + 1] != "GET"]

    def __call__(self, *args, output=None):
        self.calls.append(args)
        if args[0] == "git":
            return self.tag_commit
        assert args[:2] == ("gh", "api"), args
        endpoint = args[2]
        if self.api_error and (self.api_error_endpoint is None or self.api_error_endpoint == endpoint):
            raise self.api_error
        method = args[args.index("--method") + 1] if "--method" in args else "GET"
        root = "repos/example/repository/releases"
        if endpoint == f"{root}/tags/v1.0.0":
            # This endpoint deliberately never exposes drafts.
            if self.metadata is None or self.metadata["draft"]:
                raise subprocess.CalledProcessError(1, args, stderr="gh: Not Found (HTTP 404)")
            return json.dumps(self.metadata)
        if endpoint.startswith(f"{root}?per_page=100&page="):
            assert method == "GET", args
            page = int(parse_qs(urlparse(endpoint).query)["page"][0])
            releases = self.other_releases + ([self.metadata] if self.metadata else [])
            return json.dumps(releases[(page - 1) * 100:page * 100])
        if endpoint == root and method == "POST":
            assert self.metadata is None, "A resumed draft must not be created again."
            assert "draft=true" in args and "tag_name=v1.0.0" in args, args
            self.seed_release()
            return json.dumps(self.metadata)
        if endpoint == f"{root}/42":
            assert self.metadata is not None, args
            if method == "PATCH":
                assert self.metadata["draft"], "Public releases must never be modified."
                if "draft=false" in args:
                    self.metadata["draft"] = False
                else:
                    assert "target_commitish=example-commit" in args, args
            else:
                assert method == "GET", args
            return json.dumps(self.metadata)
        if endpoint.startswith(f"https://uploads.github.com/{root}/42/assets?name="):
            assert method == "POST" and self.metadata["draft"], args
            if self.fail_upload:
                raise subprocess.CalledProcessError(1, args)
            name = parse_qs(urlparse(endpoint).query)["name"][0]
            data = Path(args[args.index("--input") + 1]).read_bytes()
            self.remote[name] = data
            asset = {"id": 100 + len(self.remote), "name": name, "size": len(data), "state": "uploaded"}
            self.metadata["assets"].append(asset)
            if self.publish_during_upload and name == "SHA256SUMS.txt":
                self.metadata["draft"] = False
            return json.dumps(asset)
        if endpoint.startswith(f"{root}/assets/"):
            asset_id = int(endpoint.rsplit("/", 1)[1])
            asset = next(asset for asset in self.metadata["assets"] if asset["id"] == asset_id)
            if method == "DELETE":
                assert self.metadata["draft"], args
                self.metadata["assets"].remove(asset)
                self.remote.pop(asset["name"], None)
                return ""
            assert method == "GET" and "Accept: application/octet-stream" in args and output is not None, args
            data = self.remote[asset["name"]]
            if self.corrupt_download and asset["name"].endswith(".dmg"):
                data = b"corrupted"
            output.write_bytes(data)
            return ""
        raise AssertionError(f"Unexpected GitHub request: {args}")


class PublishReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.names = publisher.asset_names("1.0.0")
        for name in self.names[:2]:
            (self.directory / name).write_bytes(f"example asset {name}".encode())
        manifest = "".join(f"{publisher.digest(self.directory / name)}  {name}\n" for name in self.names[:2])
        for name in self.names[2:]:
            (self.directory / name).write_text(manifest)
        self.github = FakeGitHub()

    def tearDown(self):
        self.temporary.cleanup()

    def publish(self):
        publisher.publish("1.0.0", "example-commit", "example/repository", self.directory, self.github)

    def assert_unpublished(self):
        self.assertFalse(any("draft=false" in call for call in self.github.calls))

    def test_fresh_draft_is_created_and_published_by_id_after_download_verification(self):
        self.publish()
        self.assertFalse(self.github.metadata["draft"])
        create = next(call for call in self.github.mutations if call[2] == "repos/example/repository/releases")
        self.assertIn("draft=true", create)
        downloads = [index for index, call in enumerate(self.github.calls) if "Accept: application/octet-stream" in call]
        publish = next(index for index, call in enumerate(self.github.calls) if "draft=false" in call)
        self.assertEqual(len(downloads), 4)
        self.assertLess(max(downloads), publish)
        self.assertEqual(self.github.calls[publish][2], "repos/example/repository/releases/42")
        id_reads = [call for call in self.github.calls
                    if call[2] == "repos/example/repository/releases/42" and "--method" not in call]
        self.assertEqual(len(id_reads), 2)
        self.assertEqual(sum("/tags/" in call[2] for call in self.github.calls), 1)
        self.assertEqual(set(self.github.remote), set(self.names))

    def test_failed_upload_keeps_a_draft(self):
        self.github.fail_upload = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertTrue(self.github.metadata["draft"])
        self.assert_unpublished()

    def test_corrupt_remote_asset_keeps_a_draft(self):
        self.github.corrupt_download = True
        with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
            self.publish()
        self.assertTrue(self.github.metadata["draft"])
        self.assert_unpublished()

    def test_partial_draft_can_resume(self):
        self.github.seed_release()
        self.github.remote[self.names[0]] = b"partial upload"
        self.github.metadata["assets"] = [{"id": 77, "name": self.names[0], "size": 0, "state": "starter"}]
        self.publish()
        self.assertFalse(self.github.metadata["draft"])
        self.assertEqual(self.github.remote[self.names[0]], (self.directory / self.names[0]).read_bytes())
        self.assertTrue(any(call[2] == "repos/example/repository/releases/assets/77"
                            and "DELETE" in call for call in self.github.calls))
        self.assertFalse(any(call[2] == "repos/example/repository/releases" for call in self.github.mutations))
        self.assertTrue(any("target_commitish=example-commit" in call for call in self.github.mutations))

    def test_existing_draft_on_second_page_is_resumed_by_id(self):
        self.github.seed_release()
        self.github.other_releases = [{"id": index + 1000, "tag_name": f"v2.0.{index}", "draft": True}
                                      for index in range(100)]
        self.publish()
        self.assertFalse(self.github.metadata["draft"])
        self.assertTrue(any(call[2] == "repos/example/repository/releases?per_page=100&page=2"
                            for call in self.github.calls))
        self.assertFalse(any(call[2] == "repos/example/repository/releases" for call in self.github.mutations))

    def test_full_page_without_matching_tag_reaches_an_empty_page_before_creation(self):
        self.github.other_releases = [{"id": index + 1000, "tag_name": f"v2.0.{index}", "draft": False}
                                      for index in range(100)]
        self.publish()
        self.assertTrue(any(call[2].endswith("page=2") for call in self.github.calls))
        self.assertFalse(self.github.metadata["draft"])

    def test_listing_failure_does_not_create_a_duplicate_draft(self):
        self.github.seed_release()
        self.github.api_error_endpoint = "repos/example/repository/releases?per_page=100&page=1"
        self.github.api_error = subprocess.CalledProcessError(1, [], stderr="gh: Forbidden (HTTP 403)")
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertEqual(self.github.mutations, [])

    def test_release_becoming_public_before_verification_is_not_published_again(self):
        self.github.publish_during_upload = True
        with self.assertRaisesRegex(ValueError, "unpublished draft"):
            self.publish()
        self.assert_unpublished()

    def test_complete_public_release_is_never_modified_on_rerun(self):
        self.publish()
        original = self.github.remote.copy()
        # A rebuild can produce different archive bytes; preserve the verified public version.
        (self.directory / self.names[0]).write_bytes(b"rebuilt archive")
        manifest = "".join(f"{publisher.digest(self.directory / name)}  {name}\n" for name in self.names[:2])
        for name in self.names[2:]:
            (self.directory / name).write_text(manifest)
        self.github.calls = []
        self.publish()
        self.assertEqual(self.github.remote, original)
        self.assertEqual(self.github.mutations, [])

    def test_incomplete_public_release_is_protected_and_fails(self):
        self.github.seed_release(draft=False)
        with self.assertRaisesRegex(ValueError, "every completed asset"):
            self.publish()
        self.assertEqual(self.github.mutations, [])
        self.assert_unpublished()

    def test_invalid_local_assets_fail_before_any_remote_action(self):
        (self.directory / self.names[1]).unlink()
        with self.assertRaisesRegex(ValueError, "Missing or empty"):
            self.publish()
        self.assertEqual(self.github.calls, [])

    def test_manifests_must_cover_exactly_both_archives_without_traversal(self):
        for manifest in ["", "0" * 64 + "  ../other.zip\n",
                         (self.directory / "SHA256SUMS.txt").read_text() * 2]:
            for name in self.names[2:]:
                (self.directory / name).write_text(manifest)
            with self.assertRaises(ValueError):
                self.publish()
        self.assertEqual(self.github.calls, [])

    def test_authentication_failure_does_not_create_a_release(self):
        self.github.api_error = subprocess.CalledProcessError(1, [], stderr="gh: Unauthorized (HTTP 401)")
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertEqual(self.github.mutations, [])
        self.assert_unpublished()

    def test_version_tag_cannot_point_at_another_commit(self):
        self.github.tag_commit = "different-commit"
        with self.assertRaisesRegex(ValueError, "different commit"):
            self.publish()
        self.assert_unpublished()

    def test_invalid_version_cannot_reach_github(self):
        with self.assertRaises(ValueError):
            publisher.publish("../invalid", "example-commit", "example/repository", self.directory, self.github)
        self.assertEqual(self.github.calls, [])

    def test_binary_download_is_streamed_without_text_decoding(self):
        output = self.directory / "binary.zip"
        publisher.run(sys.executable, "-c", "import sys; sys.stdout.buffer.write(bytes([0, 255, 128, 10]))",
                      output=output)
        self.assertEqual(output.read_bytes(), bytes([0, 255, 128, 10]))


if __name__ == "__main__":
    unittest.main()

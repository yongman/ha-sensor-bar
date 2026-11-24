import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

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

    def __call__(self, *args):
        self.calls.append(args)
        if args[0] == "git":
            return self.tag_commit
        if args[1] == "api":
            if self.api_error:
                raise self.api_error
            if self.metadata is None:
                raise subprocess.CalledProcessError(1, args, stderr="gh: Not Found (HTTP 404)")
            return json.dumps(self.metadata)
        action = args[2]
        if action == "create":
            self.metadata = {"draft": True, "assets": []}
        elif action == "upload":
            if self.fail_upload:
                raise subprocess.CalledProcessError(1, args)
            for argument in args:
                path = Path(argument)
                if path.is_file():
                    self.remote[path.name] = path.read_bytes()
            self.metadata["assets"] = [{"name": name, "size": len(data), "state": "uploaded"}
                                       for name, data in self.remote.items()]
        elif action == "download":
            directory = Path(args[args.index("--dir") + 1])
            for name, data in self.remote.items():
                (directory / name).write_bytes(data)
            if self.corrupt_download:
                (directory / publisher.asset_names("1.0.0")[0]).write_bytes(b"corrupted")
        elif action == "edit" and "--draft=false" in args:
            self.metadata["draft"] = False
        return ""


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
        self.assertFalse(any("--draft=false" in call for call in self.github.calls))

    def test_download_and_verification_precede_publication(self):
        self.publish()
        self.assertFalse(self.github.metadata["draft"])
        create = next(call for call in self.github.calls if call[1:3] == ("release", "create"))
        self.assertIn("--draft", create)
        download = next(index for index, call in enumerate(self.github.calls) if call[1:3] == ("release", "download"))
        publish = next(index for index, call in enumerate(self.github.calls) if "--draft=false" in call)
        self.assertLess(download, publish)
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
        self.github.metadata = {"draft": True, "assets": []}
        self.github.remote[self.names[0]] = b"partial upload"
        self.publish()
        self.assertFalse(self.github.metadata["draft"])
        self.assertEqual(self.github.remote[self.names[0]], (self.directory / self.names[0]).read_bytes())
        edit = next(call for call in self.github.calls if "--draft=true" in call)
        self.assertEqual(edit[edit.index("--target") + 1], "example-commit")

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
        self.assertFalse(any(call[1:3] in [("release", "edit"), ("release", "upload"),
                                          ("release", "create")] for call in self.github.calls))

    def test_incomplete_public_release_is_protected_and_fails(self):
        self.github.metadata = {"draft": False, "assets": []}
        with self.assertRaisesRegex(ValueError, "every completed asset"):
            self.publish()
        self.assertFalse(any("--clobber" in call for call in self.github.calls))
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
        self.assertFalse(any(call[1:3] == ("release", "create") for call in self.github.calls))
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


if __name__ == "__main__":
    unittest.main()

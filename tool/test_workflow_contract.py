from pathlib import Path
import unittest


WORKFLOW = (
    Path(__file__).parents[1]
    / ".github"
    / "workflows"
    / "update-translation-manifest.yml"
)


class WorkflowContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = WORKFLOW.read_text(encoding="utf-8")

    def test_keeps_minimal_permission_and_serial_concurrency(self):
        self.assertIn("permissions:\n  contents: write", self.source)
        self.assertIn("group: update-translation-manifest", self.source)
        self.assertIn("cancel-in-progress: false", self.source)
        self.assertNotIn("pull-requests: write", self.source)

    def test_dispatch_uses_event_file_and_recovery_is_explicit(self):
        self.assertIn('mode="recovery"', self.source)
        self.assertIn('mode="dispatch"', self.source)
        self.assertIn('--event-file "$EVENT_FILE"', self.source)
        self.assertNotIn("releases/latest", self.source)

    def test_refreshes_main_and_reapplies_candidate_before_commit(self):
        pull = self.source.index("git pull --ff-only origin main")
        apply = self.source.index("apply_candidate", pull)
        commit = self.source.index("create_commit", apply)
        self.assertLess(pull, apply)
        self.assertLess(apply, commit)

    def test_push_retry_is_limited_and_revalidates(self):
        self.assertIn("for attempt in 1 2", self.source)
        self.assertIn("git checkout --detach origin/main", self.source)
        retry = self.source.index("git checkout --detach origin/main")
        self.assertIn("apply_candidate", self.source[retry:])
        self.assertIn("Push was rejected after the controlled retry", self.source)

    def test_only_manifest_is_staged(self):
        self.assertIn('git add -- "$manifest"', self.source)
        self.assertNotIn("git add -A", self.source)
        self.assertNotIn("git add .", self.source)

    def test_does_not_interpolate_payload_fields_into_shell(self):
        self.assertNotIn("client_payload.", self.source)
        self.assertIn("${{ github.event_path }}", self.source)
        self.assertNotIn("GITHUB_OUTPUT", self.source)

    def test_runs_tests_validation_and_diff_check_before_commit(self):
        self.assertIn("python -m unittest discover", self.source)
        self.assertIn("--mode verify", self.source)
        self.assertIn("git diff --check", self.source)


if __name__ == "__main__":
    unittest.main()

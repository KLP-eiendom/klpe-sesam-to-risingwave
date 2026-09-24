import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
import fetch_vault_secrets as fvs


class TestLoadEnvFile(unittest.TestCase):
    def _make_env_file(self, content: str) -> str:
        f = tempfile.NamedTemporaryFile(mode="w", suffix=".env", delete=False)
        f.write(content)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_basic_parse(self):
        path = self._make_env_file("A=1\nB=hello world\n")
        self.assertEqual(fvs.load_env_file(path), {"A": "1", "B": "hello world"})

    def test_skips_comments_and_blanks(self):
        path = self._make_env_file("# comment\n\nA=1\n")
        self.assertEqual(fvs.load_env_file(path), {"A": "1"})

    def test_missing_file_returns_empty(self):
        self.assertEqual(fvs.load_env_file("/nonexistent/path.env"), {})

    def test_value_with_equals_sign(self):
        path = self._make_env_file("KEY=value=with=equals\n")
        self.assertEqual(fvs.load_env_file(path), {"KEY": "value=with=equals"})


class TestFetchSecrets(unittest.TestCase):
    def _mock_read(self, data):
        def _read(_server, _token, path):
            return data.get(path, {})
        return _read

    def test_prefix_trailing_slash_added(self):
        calls = []
        with patch.object(fvs, "vault_read_kv1", side_effect=lambda s, t, p: calls.append(p) or {}):
            fvs.fetch_secrets("https://vault", "tok", "Risingwave", "dev")
        self.assertEqual(calls, ["Risingwave/dev"])

    def test_prefix_trailing_slash_not_doubled(self):
        calls = []
        with patch.object(fvs, "vault_read_kv1", side_effect=lambda s, t, p: calls.append(p) or {}):
            fvs.fetch_secrets("https://vault", "tok", "Risingwave/", "dev")
        self.assertEqual(calls, ["Risingwave/dev"])

    def test_multiple_secrets_merged(self):
        data = {"Risingwave/common": {"A": "1"}, "Risingwave/dev": {"B": "2"}}
        with patch.object(fvs, "vault_read_kv1", side_effect=self._mock_read(data)):
            result = fvs.fetch_secrets("https://vault", "tok", "Risingwave/", "common dev")
        self.assertEqual(result, {"A": "1", "B": "2"})

    def test_later_secret_wins_on_duplicate_key(self):
        data = {"Risingwave/base": {"X": "base"}, "Risingwave/dev": {"X": "dev"}}
        with patch.object(fvs, "vault_read_kv1", side_effect=self._mock_read(data)):
            result = fvs.fetch_secrets("https://vault", "tok", "Risingwave/", "base dev")
        self.assertEqual(result["X"], "dev")

    def test_comma_separated_secrets(self):
        calls = []
        with patch.object(fvs, "vault_read_kv1", side_effect=lambda s, t, p: calls.append(p) or {}):
            fvs.fetch_secrets("https://vault", "tok", "Risingwave/", "common,dev")
        self.assertEqual(calls, ["Risingwave/common", "Risingwave/dev"])


class TestMergeOrder(unittest.TestCase):
    """Vault secrets < env passthrough < localdev overrides."""

    def _make_env_file(self, content: str) -> str:
        f = tempfile.NamedTemporaryFile(mode="w", suffix=".env", delete=False)
        f.write(content)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def _run_main(self, env_content, localdev_content=""):
        env_file = self._make_env_file(env_content)
        localdev_file = self._make_env_file(localdev_content) if localdev_content else None

        vault_data = {"DBT_RW_HOST": "vault-host", "DBT_RW_PASSWORD": "secret"}

        with patch.object(fvs, "vault_read_kv1", return_value=vault_data), \
             patch.object(fvs, "vault_k8s_login", return_value="k8s-tok"):
            sys.argv = ["fetch_vault_secrets.py", env_file] + ([localdev_file] if localdev_file else [])
            buf = io.StringIO()
            with redirect_stdout(buf):
                fvs.main()
            output_lines = dict(line.split("=", 1) for line in buf.getvalue().strip().splitlines())
        return output_lines

    def test_env_passthrough_overrides_vault(self):
        env = (
            "VaultOptions__Server=https://vault\n"
            "VaultOptions__Prefix=Risingwave/\n"
            "VaultOptions__Secrets=dev\n"
            "VaultOptions__TokenId=tok\n"
            "DBT_RW_HOST=env-override\n"
        )
        result = self._run_main(env)
        self.assertEqual(result["DBT_RW_HOST"], "env-override")

    def test_localdev_overrides_everything(self):
        env = (
            "VaultOptions__Server=https://vault\n"
            "VaultOptions__Prefix=Risingwave/\n"
            "VaultOptions__Secrets=dev\n"
            "VaultOptions__TokenId=tok\n"
            "DBT_RW_HOST=env-override\n"
        )
        localdev = "DBT_RW_HOST=localdev-override\n"
        result = self._run_main(env, localdev)
        self.assertEqual(result["DBT_RW_HOST"], "localdev-override")

    def test_vault_options_not_in_output(self):
        env = (
            "VaultOptions__Server=https://vault\n"
            "VaultOptions__Prefix=Risingwave/\n"
            "VaultOptions__Secrets=dev\n"
            "VaultOptions__TokenId=tok\n"
        )
        result = self._run_main(env)
        self.assertFalse(any(k.startswith("VaultOptions__") for k in result))

    def test_sink_mode_passthrough(self):
        env = (
            "VaultOptions__Server=https://vault\n"
            "VaultOptions__Prefix=Risingwave/\n"
            "VaultOptions__Secrets=dev\n"
            "VaultOptions__TokenId=tok\n"
            "FORVALTER_SINK_MODE=paused\n"
        )
        result = self._run_main(env)
        self.assertEqual(result["FORVALTER_SINK_MODE"], "paused")


if __name__ == "__main__":
    unittest.main()

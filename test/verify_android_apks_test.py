import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class AndroidReleaseSigningTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="synthetic_promax_signing_")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.tools = self.root / "sdk" / "build-tools" / "35.0.0"
        self.tools.mkdir(parents=True)
        (self.root / "pubspec.yaml").write_text("version: 0.0.0+121\n")
        self.script = Path(__file__).resolve().parents[1] / ".github/scripts/verify-android-apks.sh"
        self.bash = shutil.which("bash") or r"C:\Program Files\Git\bin\bash.exe"
        self.env = {**os.environ, "ANDROID_HOME": (self.root / "sdk").as_posix()}

    def run_guard(
        self,
        certificate="e83be69ec2ea9cc8f418b533636c1a114824bfc05a940fca6060205f390d72b6",
        package="io.github.stillemptynow.promax",
        code=121,
        valid=True,
        version="0.0.0",
        invalid_abi=None,
        extra_signer=False,
        valid_badging=True,
    ):
        signer = self.tools / "apksigner"
        signer_body = (
            '#!/usr/bin/env bash\n'
            '[ "$1" = verify ] && [ "$2" = --print-certs ] || exit 2\n'
            f'certificate={certificate}\n'
        )
        if invalid_abi:
            filename = "app-promax-release.apk" if invalid_abi == "universal" else f"app-{invalid_abi}-promax-release.apk"
            signer_body += f'if [[ "$3" = */{filename} ]]; then certificate={"0" * 64}; fi\n'
        signer_body += 'printf "Signer #1 certificate SHA-256 digest: %s\\n" "$certificate"\n'
        if extra_signer:
            signer_body += f"printf 'Signer #2 certificate SHA-256 digest: {'1' * 64}\\n'\n"
        signer_body += f"exit {0 if valid else 1}\n"
        signer.write_text(signer_body, newline="\n")
        signer.chmod(0o755)
        aapt = self.tools / "aapt"
        aapt.write_text(
            '#!/usr/bin/env bash\n'
            '[ "$1" = dump ] && [ "$2" = badging ] || exit 2\n'
            f'echo "package: name=\'{package}\' versionCode=\'{code}\' versionName=\'{version}\'"\n'
            f'exit {0 if valid_badging else 1}\n',
            newline="\n",
        )
        aapt.chmod(0o755)
        return subprocess.run([self.bash, self.script.as_posix()], cwd=self.root, env=self.env, capture_output=True, text=True)

    def test_accepts_the_permanent_certificate_and_expected_build(self):
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count("Verified "), 4)

    def test_rejects_a_debug_certificate(self):
        self.assertNotEqual(self.run_guard(certificate="0" * 64).returncode, 0)

    def test_rejects_another_package(self):
        self.assertNotEqual(self.run_guard(package="test.synthetic.other").returncode, 0)

    def test_rejects_a_wrong_version_code(self):
        self.assertNotEqual(self.run_guard(code=120).returncode, 0)

    def test_rejects_a_wrong_version_name(self):
        self.assertNotEqual(self.run_guard(version="0.0.1").returncode, 0)

    def test_rejects_an_unverified_apk(self):
        self.assertNotEqual(self.run_guard(valid=False).returncode, 0)

    def test_rejects_an_additional_signer(self):
        self.assertNotEqual(self.run_guard(extra_signer=True).returncode, 0)

    def test_verifies_each_split_and_universal_apk(self):
        for abi in ("arm64-v8a", "armeabi-v7a", "x86_64", "universal"):
            with self.subTest(abi=abi):
                self.assertNotEqual(self.run_guard(invalid_abi=abi).returncode, 0)

    def test_rejects_unreadable_package_metadata(self):
        self.assertNotEqual(self.run_guard(valid_badging=False).returncode, 0)


if __name__ == "__main__":
    unittest.main()

"""Exercise packaging failures in disposable fixtures, never the user's running app."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class BuildSafetyTests(unittest.TestCase):
    def exercise(self, process_status, signing_status):
        fixture = tempfile.TemporaryDirectory(prefix="build-safety-", dir=ROOT / "build")
        self.addCleanup(fixture.cleanup)
        directory = Path(fixture.name)
        for name in ("scripts", "Resources", "tools", "compiled", "build/Autoeng.app/Contents/MacOS"):
            (directory / name).mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "scripts/build-app.sh", directory / "scripts/build-app.sh")
        shutil.copy2(ROOT / "Resources/Info.plist", directory / "Resources/Info.plist")
        (directory / "compiled/Autoeng").write_text("new executable")
        installed = directory / "build/Autoeng.app/Contents/MacOS/Autoeng"
        installed.write_text("original executable")
        mocks = {
            "swift": '#!/bin/bash\ncase "$*" in *--show-bin-path*) echo "$AUTOENG_TEST_BINARY_DIRECTORY";; esac\nexit 0\n',
            "pgrep": f"#!/bin/bash\nexit {process_status}\n",
            "codesign": f"#!/bin/bash\nexit {signing_status}\n",
        }
        for name, contents in mocks.items():
            path = directory / "tools" / name; path.write_text(contents); path.chmod(0o700)
        helper = directory / "scripts/sign-app.sh"
        helper.write_text(f"#!/bin/bash\nexit {signing_status}\n"); helper.chmod(0o700)
        environment = dict(os.environ, PATH=f"{directory / 'tools'}:{os.environ['PATH']}",
                           AUTOENG_TEST_BINARY_DIRECTORY=str(directory / "compiled"))
        result = subprocess.run([str(directory / "scripts/build-app.sh")], env=environment,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return result, installed

    def test_running_app_is_not_overwritten(self):
        result, installed = self.exercise(0, 0)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(installed.read_text(), "original executable")

    def test_process_inspection_error_fails_closed(self):
        result, installed = self.exercise(3, 0)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(installed.read_text(), "original executable")

    def test_signing_failure_keeps_previous_bundle(self):
        result, installed = self.exercise(1, 1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(installed.read_text(), "original executable")

    def test_stopped_app_and_valid_signature_install_new_bundle(self):
        result, installed = self.exercise(1, 0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(installed.read_text(), "new executable")


if __name__ == "__main__":
    unittest.main()

"""Sign Autoeng with a stable identity; never print keychain passwords."""
import fcntl
import os
from pathlib import Path
import plistlib
import re
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
DIRECTORY = ROOT / ".local-signing"


def run(arguments, *, capture=False):
    result = subprocess.run(arguments, text=True, stdout=subprocess.PIPE if capture else None)
    if result.returncode:
        raise RuntimeError(f"{Path(arguments[0]).name} failed (exit {result.returncode})")
    return result.stdout if capture else None


def search_paths():
    return shlex.split(run(["security", "list-keychains", "-d", "user"], capture=True))


def sign(bundle):
    with (bundle / "Contents/Info.plist").open("rb") as source:
        identifier = plistlib.load(source).get("CFBundleIdentifier")
    if identifier != "local.autoeng.app":
        raise RuntimeError("signing helper only accepts the Autoeng bundle identifier")
    external = os.environ.get("AUTOENG_SIGNING_IDENTITY")
    if external:
        if external == "-":
            raise RuntimeError("ad hoc signing cannot preserve permission identity across builds")
        run(["codesign", "--force", "--sign", external, "--timestamp=none", str(bundle)])
        return
    for name in ("identity.sha1", "certificate.pem", "password", "autoeng.keychain-db"):
        if not (DIRECTORY / name).is_file():
            raise RuntimeError("stable signing identity missing; run setup-local-signing.sh and trust-local-signing.sh once")
    identity = (DIRECTORY / "identity.sha1").read_text().strip()
    fingerprint = run(["openssl", "x509", "-in", str(DIRECTORY / "certificate.pem"),
                       "-noout", "-fingerprint", "-sha1"], capture=True).split("=", 1)[1].strip().replace(":", "")
    if not re.fullmatch(r"[0-9A-Fa-f]{40}", identity) or identity != fingerprint:
        raise RuntimeError("local signing certificate does not match the saved identity")
    run(["openssl", "x509", "-in", str(DIRECTORY / "certificate.pem"), "-noout", "-checkend", "0"], capture=True)
    keychain = str(DIRECTORY / "autoeng.keychain-db")
    password = (DIRECTORY / "password").read_text().strip()
    with (DIRECTORY / "signing.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("another local signing operation is running") from None
        original = search_paths()
        added = keychain not in original
        try:
            # codesign needs this search-list entry even with --keychain.
            if added:
                run(["security", "list-keychains", "-d", "user", "-s", *original, keychain])
            # Secret-bearing command arguments must never enter exceptions/logs.
            unlocked = subprocess.run(["security", "unlock-keychain", "-p", password, keychain],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if unlocked.returncode:
                raise RuntimeError("cannot unlock project signing keychain")
            requirement = f'designated => identifier "local.autoeng.app" and certificate leaf = H"{identity}"'
            run(["codesign", "--force", "--sign", identity, "--keychain", keychain,
                 "--timestamp=none", "--requirements", "=" + requirement, str(bundle)])
        finally:
            subprocess.run(["security", "lock-keychain", keychain], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if added:
                # Preserve changes to other keychains made during signing.
                current = search_paths()
                if keychain in current:
                    run(["security", "list-keychains", "-d", "user", "-s",
                         *(path for path in current if path != keychain)])


def main():
    if len(sys.argv) != 2:
        raise RuntimeError("usage: sign-app.sh app-bundle")
    bundle = Path(sys.argv[1]).resolve()
    sign(bundle)
    run(["codesign", "--verify", "--strict", str(bundle)])


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)

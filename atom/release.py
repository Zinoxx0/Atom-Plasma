"""`rice.py release VERSION [--critical SUMMARY] [--summary TEXT]`: cut a release (maintainers).

Checks the version is a real one and newer than this build, the tree is clean and the changelog has an
"## Unreleased" section; then sets atom/__init__.py's __version__, dates the changelog section, commits
"Release VERSION" and makes the annotated tag vVERSION whose message the updater reads:

    Atom Plasma 1.2.0
    Critical: yes             (only with --critical: everyone below it is asked to update now)
    Summary: one line for the notification

Pushing is yours: git push origin main vVERSION (the updater only sees pushed tags)."""
import re
import sys
from datetime import date

from . import util
from .util import ROOT
from .version import Version


def git(*a):
    return util.run("git", "-C", str(ROOT), *a, quiet=True)


def main(args):
    if not args or args[0].startswith("-"):
        sys.exit(__doc__)
    v = Version.parse(args[0])
    if not v:
        sys.exit(f"{args[0]}: not a version (1.2.0, 1.3.0-beta.1, 1.3.0-alpha.4)")
    opt = lambda k: args[args.index(k) + 1] if k in args and args.index(k) + 1 < len(args) else ""
    critical, summary = opt("--critical"), opt("--summary") or opt("--critical")
    init = ROOT / "atom/__init__.py"
    cur = Version.parse(re.search(r'__version__\s*=\s*"([^"]+)"', init.read_text())[1])
    if cur and not v > cur:
        sys.exit(f"{v} isn't newer than this build ({cur})")
    if git("status", "--porcelain", "--untracked-files=no").stdout.strip():
        sys.exit("commit or stash your changes first")
    if git("rev-parse", "--verify", "--quiet", v.tag).returncode == 0:
        sys.exit(f"{v.tag} exists already")
    log = ROOT / "CHANGELOG.md"
    text = log.read_text()
    if "## Unreleased" not in text:
        sys.exit("CHANGELOG.md has no '## Unreleased' section to release")
    log.write_text(text.replace("## Unreleased", f"## Unreleased\n\n## {v} ({date.today().isoformat()})", 1))
    init.write_text(re.sub(r'__version__\s*=\s*"[^"]+"', f'__version__ = "{v}"', init.read_text()))
    r = git("commit", "-q", "-m", f"Release {v}", "--", "atom/__init__.py", "CHANGELOG.md")
    if r.returncode:
        sys.exit("commit failed: " + (r.stderr or r.stdout).strip())
    msg = f"Atom Plasma {v}\n\n" + ("Critical: yes\n" if critical else "") + (f"Summary: {summary}\n" if summary else "")
    r = git("tag", "-a", v.tag, "-m", msg)
    if r.returncode:
        sys.exit("tag failed: " + (r.stderr or r.stdout).strip())
    print(f"Released {v} ({v.channel}{', critical' if critical else ''}). Publish it: git push origin HEAD {v.tag}")

"""Atom Plasma's versions and release channels (semver with a pre-release tag for the channel):

    1.2.0           stable          (a stable fix: 1.2.1)
    1.3.0-beta.2    beta            the next features, nearly ready
    1.3.0-alpha.5   alpha           the newest work, may break

A channel takes its own releases and every steadier one: stable only stable, beta stable + beta, alpha all.
Order is semver's: 1.3.0-alpha.5 < 1.3.0-beta.1 < 1.3.0 < 1.3.1. Releases are git tags `v<version>`."""
import re

CHANNELS = ("stable", "beta", "alpha")
_RX = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta)\.(\d+))?$")
_RANK = {"alpha": 0, "beta": 1, None: 2}


class Version:
    __slots__ = ("major", "minor", "patch", "pre", "num")

    def __init__(self, major, minor, patch, pre=None, num=0):
        self.major, self.minor, self.patch, self.pre, self.num = major, minor, patch, pre, num

    @classmethod
    def parse(cls, s):
        """'1.3.0-beta.2' or 'v1.3.0-beta.2' -> Version; None when it isn't one."""
        m = _RX.match(str(s or "").strip())
        if not m:
            return None
        return cls(int(m[1]), int(m[2]), int(m[3]), m[4], int(m[5] or 0))

    @property
    def channel(self):
        return self.pre or "stable"

    def key(self):
        return (self.major, self.minor, self.patch, _RANK[self.pre], self.num)

    def __lt__(self, o): return self.key() < o.key()
    def __le__(self, o): return self.key() <= o.key()
    def __gt__(self, o): return self.key() > o.key()
    def __ge__(self, o): return self.key() >= o.key()
    def __eq__(self, o): return isinstance(o, Version) and self.key() == o.key()
    def __hash__(self): return hash(self.key())

    def __str__(self):
        return f"{self.major}.{self.minor}.{self.patch}" + (f"-{self.pre}.{self.num}" if self.pre else "")

    def __repr__(self):
        return f"Version({self})"

    @property
    def tag(self):
        return f"v{self}"


def allowed(v, channel):
    """Does a channel take this release? (stable < beta < alpha in what they take)"""
    want = CHANNELS.index(channel) if channel in CHANNELS else 0
    return CHANNELS.index(v.channel) <= want


def newest(versions, channel):
    ok = [v for v in versions if allowed(v, channel)]
    return max(ok) if ok else None

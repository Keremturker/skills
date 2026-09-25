#!/usr/bin/env python3
"""Blocks secrets from being written into source files and sensitive files from being committed.

PreToolUse hook. Exit 2 + stderr blocks the tool call and the message reaches the model.
Anything unexpected (bad input, missing field) exits 0: this guard must never block ./gradlew.
"""
from __future__ import annotations

import json
import re
import sys

SECRET_PATTERNS = [
    ("AWS access key", re.compile(r"\b(AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b")),
    ("private key", re.compile(r"-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----")),
    ("JSON Web Token", re.compile(r"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}")),
    ("URL with an embedded password", re.compile(r"\b[a-z][a-z0-9+.\-]*://[^\s:/@]+:[^\s@/]+@")),
    ("GitHub token", re.compile(r"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}\b|\bgithub_pat_[A-Za-z0-9_]{50,}")),
    ("GitLab token", re.compile(r"\bglpat-[A-Za-z0-9_\-]{20}\b")),
]

# In a .properties file any value is plain text; in code only a quoted literal is, since
# System.getenv("...") or keystoreProperties["..."] is the way secrets should be read.
PROPERTIES_KEYSTORE_PASSWORD = re.compile(r"(?im)^\s*(storePassword|keyPassword)\s*=\s*\S+")
CODE_KEYSTORE_PASSWORD = re.compile(r"(storePassword|keyPassword)\s*=\s*\"[^\"$]+\"")

# The sanctioned secret stores. Writing them is allowed; committing them is blocked below.
SECRET_STORE = re.compile(r"(^|/)(local\.properties|keystore\.properties|\.env(\.[^/]*)?)$")

# A path ends at whitespace, a quote, a shell separator or a closing parenthesis.
_END = r"""([\s"';&|)]|$)"""
SENSITIVE_PATH = re.compile(
    r"""(^|[\s/"'(])(local\.properties|keystore\.properties|\.env(\.[\w.-]+)?)""" + _END
    + r"|\.(jks|keystore|p12|mobileprovision)" + _END
)

ADVICE = (
    "Keep secrets out of source: put them in local.properties or an environment variable "
    "and read them through BuildConfig or an expect/actual accessor."
)


def is_exempt(path: str) -> bool:
    return path.endswith(".md") or re.search(r"/src/\w*Test/", path) is not None


def check_write(tool_input: dict) -> str | None:
    path = tool_input.get("file_path", "")
    if is_exempt(path) or SECRET_STORE.search(path):
        return None
    text = "\n".join(
        str(tool_input.get(key, "")) for key in ("content", "new_string")
    )
    for edit in tool_input.get("edits", []) or []:
        text += "\n" + str(edit.get("new_string", ""))
    keystore = PROPERTIES_KEYSTORE_PASSWORD if path.endswith(".properties") else CODE_KEYSTORE_PASSWORD
    for name, pattern in SECRET_PATTERNS + [("plain-text keystore password", keystore)]:
        if pattern.search(text):
            return f"Blocked: this change to {path} contains what looks like a {name}. {ADVICE}"
    return None


def check_bash(tool_input: dict) -> str | None:
    command = tool_input.get("command", "")
    if not re.search(r"\bgit\b", command):
        return None
    if "--no-verify" in command:
        return "Blocked: git hooks must not be skipped (--no-verify)."
    if re.search(r"\bgit\s+(add|commit)\b", command) and SENSITIVE_PATH.search(command):
        return (
            "Blocked: this git command stages or commits a sensitive file "
            "(local.properties, keystore.properties, .env, *.jks, *.keystore, *.p12, *.mobileprovision)."
        )
    return None


def main() -> int:
    try:
        event = json.load(sys.stdin)
        tool = event.get("tool_name", "")
        tool_input = event.get("tool_input", {}) or {}
        if tool in ("Write", "Edit", "MultiEdit"):
            reason = check_write(tool_input)
        elif tool == "Bash":
            reason = check_bash(tool_input)
        else:
            reason = None
    except Exception:
        return 0
    if reason:
        print(reason, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3

import argparse
import pathlib
import re
import subprocess
import sys

EXPECTED_NAME = b"Philipp Meder"
EXPECTED_EMAIL = b"260910895+mm20261@users.noreply.github.com"
TRAILER_PATTERN = re.compile(
    br"(?i)^Co-Authored-By[ \t]*:[ \t]*(.*?)[ \t]*$"
)


def git(repo: str, *args: str) -> bytes:
    return subprocess.check_output(
        ["git", "-C", repo, *args],
        stderr=subprocess.STDOUT,
    )


def commits(repo: str) -> list[str]:
    output = git(
        repo,
        "rev-list",
        "--topo-order",
        "--reverse",
        "refs/heads/main",
    )
    return output.decode("ascii").splitlines()


def metadata(repo: str, sha: str) -> list[bytes]:
    output = git(
        repo,
        "show",
        "-s",
        (
            "--format="
            "%T%x00%P%x00"
            "%an%x00%ae%x00"
            "%cn%x00%ce%x00"
            "%aI%x00%cI"
        ),
        sha,
    ).rstrip(b"\n")
    fields = output.split(b"\x00")
    if len(fields) != 8:
        raise RuntimeError(f"unexpected metadata field count for {sha}")
    return fields


def raw_message(repo: str, sha: str) -> bytes:
    raw_commit = git(repo, "cat-file", "commit", sha)
    _, separator, message = raw_commit.partition(b"\n\n")
    if not separator:
        raise RuntimeError(f"commit {sha} has no header/message separator")
    return message


def clean_message(message: bytes) -> bytes:
    kept_lines: list[bytes] = []
    removed_target = False

    for line in message.splitlines(keepends=True):
        logical_line = line.rstrip(b"\r\n")
        match = TRAILER_PATTERN.fullmatch(logical_line)
        if match:
            value = match.group(1).lower()
            if b"claude" in value or b"anthropic" in value:
                removed_target = True
                continue
        kept_lines.append(line)

    rewritten = b"".join(kept_lines)
    if removed_target:
        rewritten = rewritten.rstrip(b"\r\n") + b"\n"
    return rewritten


def contains_target_trailer(message: bytes) -> bool:
    for line in message.splitlines():
        match = TRAILER_PATTERN.fullmatch(line.rstrip(b"\r\n"))
        if not match:
            continue
        value = match.group(1).lower()
        if b"claude" in value or b"anthropic" in value:
            return True
    return False


def read_commit_map(path: pathlib.Path) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for index, line in enumerate(path.read_text(encoding="ascii").splitlines()):
        if index == 0 and line.strip() == "old                                      new":
            continue
        parts = line.split()
        if len(parts) != 2:
            continue
        old_sha, new_sha = parts
        if new_sha == "0" * 40:
            raise RuntimeError(f"commit was deleted: {old_sha}")
        mapping[old_sha] = new_sha
    return mapping


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--before", required=True)
    parser.add_argument("--after", required=True)
    parser.add_argument("--commit-map", required=True)
    args = parser.parse_args()

    before_commits = commits(args.before)
    after_commits = commits(args.after)
    mapping = read_commit_map(pathlib.Path(args.commit_map))

    if len(before_commits) != len(after_commits):
        fail(
            f"commit count changed: "
            f"{len(before_commits)} -> {len(after_commits)}"
        )

    missing = [sha for sha in before_commits if sha not in mapping]
    if missing:
        fail(f"commit map misses {len(missing)} reachable commits")

    mapped_commits = [mapping[sha] for sha in before_commits]
    if set(mapped_commits) != set(after_commits):
        fail("mapped commit set differs from rewritten reachable set")

    for old_sha in before_commits:
        new_sha = mapping[old_sha]
        old_meta = metadata(args.before, old_sha)
        new_meta = metadata(args.after, new_sha)

        if old_meta[0] != new_meta[0]:
            fail(f"tree changed: {old_sha} -> {new_sha}")

        old_parents = old_meta[1].decode("ascii").split()
        new_parents = new_meta[1].decode("ascii").split()
        expected_parents = [mapping[parent] for parent in old_parents]
        if expected_parents != new_parents:
            fail(f"parent topology changed: {old_sha} -> {new_sha}")

        if new_meta[2] != EXPECTED_NAME:
            fail(f"unexpected author name at {new_sha}")
        if new_meta[3] != EXPECTED_EMAIL:
            fail(f"unexpected author email at {new_sha}")
        if new_meta[4] != EXPECTED_NAME:
            fail(f"unexpected committer name at {new_sha}")
        if new_meta[5] != EXPECTED_EMAIL:
            fail(f"unexpected committer email at {new_sha}")
        if old_meta[6] != new_meta[6]:
            fail(f"author timestamp changed at {old_sha}")
        if old_meta[7] != new_meta[7]:
            fail(f"committer timestamp changed at {old_sha}")

        old_message = raw_message(args.before, old_sha)
        new_message = raw_message(args.after, new_sha)
        if new_message != clean_message(old_message):
            fail(f"unexpected message change at {old_sha}")
        if contains_target_trailer(new_message):
            fail(f"target co-author trailer remains at {new_sha}")

    old_tip = git(
        args.before,
        "rev-parse",
        "refs/heads/main",
    ).decode("ascii").strip()
    new_tip = git(
        args.after,
        "rev-parse",
        "refs/heads/main",
    ).decode("ascii").strip()
    if mapping[old_tip] != new_tip:
        fail("rewritten main tip does not match commit map")

    print(f"PASS: {len(before_commits)} commits verified")
    print(f"old tip: {old_tip}")
    print(f"new tip: {new_tip}")


if __name__ == "__main__":
    main()

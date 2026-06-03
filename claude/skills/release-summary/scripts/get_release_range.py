#!/usr/bin/env python3
"""Find the commit range between last prod push and current release for a conveyor.

Usage:
    python3 get_release_range.py <conveyor_id>

Example:
    python3 get_release_range.py surreal/aria_ai_interactions

Output (JSON):
    {
        "conveyor_id": "surreal/aria_ai_interactions",
        "prod_release": "R620",
        "prod_commit": "5881208446e9",
        "current_release": "R657",
        "current_commit": "c3c88cd60bcc",
        "error": null
    }
"""

import json
import re
import subprocess
import sys


def run(cmd: list[str], timeout: int = 60) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return result.stdout + result.stderr


def extract_json_array(text: str) -> list:
    """Extract JSON array from output that may contain stderr warnings."""
    match = re.search(r"^\[.*?\n\]", text, re.DOTALL)
    if match:
        return json.loads(match.group(0))
    return json.loads(text)


def find_last_prod_push(conveyor_id: str) -> dict:
    raw = run(["conveyor", "release", "status", "-c", conveyor_id, "-l", "100", "-j"])
    releases = extract_json_array(raw)

    prod_release = None
    for rel in releases:
        nodes = rel.get("nodes", [])
        for node in nodes:
            if "prod" in node.get("name", "").lower():
                if node.get("status", "").lower() == "succeeded":
                    prod_release = rel
                    break
        if prod_release:
            break

    if not prod_release:
        return {"error": "No successful prod push found in last 100 releases"}

    current = releases[0] if releases else None

    return {
        "conveyor_id": conveyor_id,
        "prod_release": f"R{prod_release['release_number']}",
        "prod_commit": prod_release.get("commit_hash", ""),
        "current_release": f"R{current['release_number']}" if current else None,
        "current_commit": current.get("commit_hash", "") if current else None,
        "error": None,
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 get_release_range.py <conveyor_id>", file=sys.stderr)
        sys.exit(1)
    result = find_last_prod_push(sys.argv[1])
    print(json.dumps(result, indent=2))

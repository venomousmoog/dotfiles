# Reviewer Map

Maps directory patterns to reviewer identifiers. Edit this to match your team structure.

| Directory Pattern | Reviewer | Notes |
|---|---|---|
| `surreal/aria_ai/` | aria_ai | Aria AI team |

## How Matching Works

The first matching pattern wins. Patterns are checked against the primary directory of changed files (the directory containing the most changed files).

## Adding Entries

Add rows to the table above. The reviewer value should be a valid Phabricator reviewer identifier (oncall name, username, or team tag).

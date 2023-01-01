#!/usr/bin/env python3
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import fnmatch
import glob
import os
import pathlib

# DISCLAIMER!
# the ignore syntax is very similar to .gitignore - but not
# a complete implementation, nor is it at all optimal.  Don't
# grab this thinking you're getting a gitignore parser

# given a full file path,
# returns true if the file should be ignored based on the
# tree of ignore paths.
def check(file, ignore_file=".clang-tidy-ignore"):
    closest_path = file

    while True:
        previous_path = closest_path
        closest_path = os.path.dirname(previous_path)
        if closest_path == previous_path:
            break

        ignore_file_path = os.path.join(closest_path, ignore_file)
        if os.path.isfile(ignore_file_path):
            with open(ignore_file_path, "r") as f:
                lines = f.readlines()

                # process globs and strip comments and trailing
                # newlines
                instructions = []
                for line in lines:
                    stripped = line.strip()
                    if len(stripped) > 0 and not stripped.startswith("#"):
                        instructions.append(stripped)

                relpath = os.path.relpath(file, closest_path)
                if match_file_ignore(relpath, instructions):
                    return True

    return False


def match_file_ignore(file, instructions):
    for instruction in instructions:
        # match it as a glob pattern
        if fnmatch.fnmatch(file, instruction):
            return True

        # match as a directory prefix
        if fnmatch.fnmatch(file, os.path.join(instruction, "*")):
            return True

    return False

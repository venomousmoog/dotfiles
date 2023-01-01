#!/usr/bin/env python3
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import argparse
import os
import subprocess
import sys
import zipfile

from b import default_mode
from build_aishell import build_aishell
from common_tools import get_buck_root

# for calling the script directly...
if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        prog="deploy_unity.py", description="build all aishell bits"
    )
    parser.add_argument("path", type=str, help="unity target project folder")
    parser.add_argument(
        "--mode", type=str, help="target buck mode", default=default_mode
    )
    args = parser.parse_args()

    build_aishell(args.mode)

    # now that we've built packages, let's unzip them into the target project:
    aishell_root = os.path.join(get_buck_root(), "research/rocktenn/projects/aishell")
    artifact_root = os.path.join(get_buck_root(), "arvr/projects/osiris/artifacts")

    unity_path = os.path.join(args.path, "Packages")
    if not os.path.exists(unity_path):
        print(f"target path {unity_path} does not exist")
        sys.exit(1)

    unity_packages = [
        "com.frl.arvr.bluebox",
        "com.frl.rocktenn.aishell",
    ]

    for package in unity_packages:
        artifact_src = os.path.join(artifact_root, f"{package}.zip")
        with zipfile.ZipFile(artifact_src, "r") as temp_zipf:
            print(f"unzipping [{artifact_src}] into [{unity_path}]")
            temp_zipf.extractall(unity_path)

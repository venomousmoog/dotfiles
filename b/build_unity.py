#!/usr/bin/env python3

import argparse
import os
import subprocess
import sys

from b import buildq
from b import default_mode
from common_tools import change_cwd
from common_tools import get_buck_root
from queries import default_targets

unity_configs = [
    "bluebox_unity_package",
    "aishell_unity_package",
    "aishell_unity_example",
    "aishell_unity_combined_packages",
]


def build_unity(mode):
    osiris_root = os.path.join(get_buck_root(), "arvr/projects/osiris/")

    with change_cwd(osiris_root):
        osiris_mode = mode[6:]
        cmd = (
            ["python3", "osiris_update_all.py", "--target_configs"]
            + unity_configs
            + ["--buck_override_mode", osiris_mode]
        )
        print(cmd)
        result = subprocess.call(cmd)
        if result != 0:
            print("osiris build failed")
            sys.exit(result)


# for calling the script directly...
if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        prog="build_aishell.py", description="build all aishell bits"
    )
    parser.add_argument(
        "--mode", type=str, help="target buck mode", default=default_mode
    )
    args = parser.parse_args()

    build_unity(args.mode)

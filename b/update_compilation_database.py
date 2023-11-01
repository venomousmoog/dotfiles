#!/usr/bin/env python3
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import argparse
import json
import os
import subprocess
import sys

import queries
from b import buck_query
from b import default_mode
from b import find_output
from b import invoke_buck
from common_tools import change_cwd
from common_tools import get_buck_root
from common_tools import pretty_targets
from common_tools import temporary_filename
from merge_compilation_commands import merge_compilation_commands

buck_root = get_buck_root()
default_output_file = os.path.join(buck_root, ".vscode/compile_commands.json")


def update_compilation_database(
    output_file=default_output_file,
    mode=default_mode,
    target_directory=os.getcwd(),
    target_query=queries.default_targets,
    build=False,
    overwrite=False,
    exclude_query=None,
):
    with change_cwd(target_directory):
        # query buck for all the targets recursively
        if exclude_query != None:
            full_query = f"({target_query}) - ({exclude_query})"
        else:
            full_query = target_query

        lines = buck_query([mode], full_query)

        with temporary_filename() as flagsfile:
            with open(flagsfile, "w") as f:
                for target in lines:
                    f.write(target + "#compilation-database\n")
                    if build:
                        f.write(target + "\n")

            # now, invoke buck to build the compilation databases:
            build_database = invoke_buck(["build", mode, f"@{flagsfile}"])

        # now, we have generated a bunch of compilation databases, lets merge them all
        # into the root database
        artifacts = []
        build_results = build_database["results"]
        for rule, result in build_results.items():
            if result["success"]:
                output = find_output(result)
                if "output" != None and output.endswith("compile_commands.json"):
                    artifact = output
                    artifacts.append(os.path.join(buck_root, artifact))
                else:
                    print(f"could not find output for: [{rule}]")

    if not overwrite and os.path.isfile(output_file):
        # go ahead and stick this at the front - later elements take precedence
        # if there's a repeat (we should probably eventually be smart and merge)
        # compile paths, but not at the moment.
        artifacts.insert(0, output_file)

    merge_compilation_commands(artifacts, [], output_file)


# for calling the script directly...
if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        prog="update_compilation_database",
        description="merge compilation_commands.json files together",
    )
    parser.add_argument(
        "--build",
        help="build all targets in addition to generating a compilation database",
        action="store_const",
        const=True,
    )
    parser.add_argument(
        "--mode", type=str, help="target buck mode", default=default_mode
    )
    parser.add_argument(
        "--target-directory",
        type=str,
        help="root directory from which to run the buck query",
        default=os.getcwd(),
    )
    parser.add_argument(
        "--target-query",
        type=str,
        help="target buck query",
        default=queries.default_targets,
    )
    parser.add_argument(
        "--output-file",
        type=str,
        help="target path for compile commands json file",
        default=default_output_file,
    )
    parser.add_argument(
        "--overwrite",
        help="overwrite the target file rather than merging with it",
        action="store_const",
        const=True,
    )
    parser.add_argument(
        "--exclude-query", type=str, help="query for excluded targets", default=None
    )
    args = parser.parse_args()

    update_compilation_database(
        args.output_file,
        args.mode,
        args.target_directory,
        args.target_query,
        args.build,
        args.overwrite,
        args.exclude_query,
    )

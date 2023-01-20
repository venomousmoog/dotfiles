#!/usr/bin/env python3

import argparse
import json
import os
import subprocess

import common_tools

script_dir = os.path.dirname(os.path.realpath(__file__))


def merge_compilation_commands(sources, paths, output):
    compile_commands = {}

    def import_file(input_path):
        with open(input_path, "r") as input_file:
            compile_set = json.load(input_file)
            for item in compile_set:
                key = (item["directory"], item["file"])
                compile_commands[key] = item

    for input_path in sources:
        import_file(input_path)

    for input_path in paths:
        for root, _, files in os.walk(input_path):
            for filename in files:
                if filename == "compile_commands.json":
                    import_file(os.path.join(root, filename))

    # post-process the compile commands to skip the external flags
    # because nobody really honors those
    for entry in compile_commands.values():
        args = entry["arguments"]
        for i in range(len(args)):
            args[i] = args[i].replace("/external:I", "/I")

    with open(os.path.join(os.getcwd(), output), "w") as output_file:
        json.dump(
            list(compile_commands.values()), output_file, sort_keys=False, indent=2
        )

    print(f"generated database with {len(compile_commands)} artifacts")


# for calling the script directly...
if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        prog="merge_compilation_commands",
        description="merge compilation_commands.json files together",
    )
    parser.add_argument("--sources", help="files to combine", nargs="+", default=[])
    parser.add_argument("--sourcepath", help="files to combine", nargs="+", default=[])
    parser.add_argument(
        "--output",
        help="output",
        type=str,
        default=os.path.join(common_tools.get_buck_root(), "compile_commands.json"),
    )
    args = parser.parse_args()
    print(args)

    merge_compilation_commands(args.sources, args.sourcepath, args.output)

#!/usr/bin/env python3
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import argparse
import fnmatch
import glob
import logging
import os
import platform
import subprocess
import sys
import tempfile
from pathlib import Path

import ignore
import queries
from b import buck_query
from common_tools import (
    change_cwd,
    emphasis_color,
    enable_console_colors,
    error_color,
    exec_lines,
    filter_extensions,
    get_buck_root,
    pretty_targets,
    success_color,
)
from update_compilation_database import update_compilation_database

tidy_extensions = [".cpp", ".h", ".cc", ".c"]

if platform.system() == "Linux":
    default_buck_mode = "@arvr/mode/linux/opt-stripped"
else:
    default_buck_mode = "@arvr/mode/win/clang/debug"


def find_file_targets(files, buck_mode):
    path_files = []
    for f in files:
        for m in glob.glob(f):
            path_files.append(os.path.join(os.getcwd(), m))

    filtered_files = filter_extensions(path_files, tidy_extensions)
    if len(filtered_files) == 0:
        print(error_color("no files with valid extensions found"))
        sys.exit(1)

    # query buck for our files to see the closure of interesting targets:
    query_string = "kind('cxx_binary|cxx_library|cxx_test', owner('%s')) - kind('prebuilt_cxx_library', owner('%s'))"
    targets = buck_query([buck_mode], query_string, filtered_files, quiet=True)

    # if we can't find any relevant targets, we can be done:
    if len(targets) == 0:
        target_query = ""
    else:
        target_query = "set('{0}')".format("' '".join(targets))

    return (filtered_files, target_query)


def build_file_list(target_files, specified_files):
    # excluded if it's in the exclusion list, or if it's not the specified single_file
    def file_list_contains(list, file):
        for f in list:
            if os.path.samefile(f, file):
                return True
        return False

    def is_excluded_file(file):
        if specified_files != None and not file_list_contains(specified_files, file):
            return True
        else:
            ig = ignore.check(file)
            return ig

    files = []
    for f in target_files:
        full_path = os.path.join(get_buck_root(), f)
        if not is_excluded_file(full_path):
            files.append(full_path)

    return files


def find_diff_files():
    hg_lines = exec_lines(["hg", "whereami"])
    if len(hg_lines) != 1:
        print(error_color("unable to query for current diff"))
    diff = hg_lines[0].strip()

    # strip the mode (M_ or A_) off of the file string that comes back from mercurial
    return list(
        map(
            lambda x: x[2:], sorted(exec_lines(["hg", "status", "--change", diff, "."]))
        )
    )


def invoke_tidy(db_dir, files, fix, fix_errors, errors_only, use_runner, export_fixes):
    # TODO - we don't have the runner enabled by default because phabricator doesn't have
    # pyyaml installed by default, and on windows the runner regex processing doesn't escape paths.
    if platform.system() == "Linux":
        clang_tidy_path = os.path.join(
            get_buck_root(), "arvr/third-party/toolchains/platform009/build/llvm-fb/bin"
        )
    else:
        clang_tidy_path = os.path.join(
            get_buck_root(), "third-party\\toolchains\\llvm\\9.0.1\\bin\\windows"
        )
    clang_tidy_exe = os.path.join(clang_tidy_path, "clang-tidy")

    if use_runner:
        clang_tidy_runner = os.path.join(
            get_buck_root(),
            "arvr/third-party/toolchains/platform009/build/llvm-fb/share/clang/run-clang-tidy.py",
        )

        clang_tidy_cmd = [
            "python3",
            clang_tidy_runner,
            f"-clang-tidy-binary",
            clang_tidy_exe,
            "-format",
            "-style=file",
        ]
    else:
        clang_tidy_cmd = [
            clang_tidy_exe,
            "-format-style=file",
        ]

    clang_tidy_cmd.extend(
        [
            f"-p={db_dir}",
            #   "--quiet",
            #   "-dump-config"
        ]
    )

    if fix:
        clang_tidy_cmd.append("-fix")
    if fix_errors:
        clang_tidy_cmd.append("-fix-errors")
    if errors_only:
        clang_tidy_cmd.append("--checks=-*,google-build-namespaces")
    if export_fixes != None:
        clang_tidy_cmd.append(f"--export-fixes={export_fixes}")

    print(emphasis_color("invoking clang-tidy"))
    print(clang_tidy_cmd)
    for f in pretty_targets(files):
        print("  " + f)
    clang_tidy_cmd.extend(files)

    if platform.system() == "Linux":
        result = subprocess.call(clang_tidy_cmd, stderr=subprocess.DEVNULL)
    else:
        result = subprocess.call(clang_tidy_cmd)

    return result


def run_clang_tidy(
    target_directory=os.getcwd(),
    target_query=queries.buildable_targets,
    buck_mode=default_buck_mode,
    use_runner=False,
    fix=False,
    fix_errors=False,
    errors_only=False,
    files=None,
    export_fixes=None,
    diff_only=False,
):
    enable_console_colors()

    with change_cwd(target_directory):
        if diff_only:
            print(emphasis_color("finding files in the current diff"))
            files = find_diff_files()

        # if we're processing a specific file set, adjust our query to find those targets
        if files != None:
            print(emphasis_color("finding targets for requested files"))

            specified_files, target_query = find_file_targets(files, buck_mode)
            if len(specified_files) == 0:
                print(
                    error_color(
                        f"unable to find any targets for files {filtered_files}"
                    )
                )
                sys.exit(1)

            if len(target_query) == 0:
                print(emphasis_color("no relevant targets found."))
                sys.exit(0)

        else:
            print(emphasis_color(f"tidying all buildable files from {os.getcwd()}"))
            specified_files = None

        # we need a temporary directory here because clang-tidy will search a directory, not a path for a compile_commands.json file.
        with tempfile.TemporaryDirectory() as database_directory:
            print(emphasis_color("generating compilation database"))
            compile_commands = os.path.join(database_directory, "compile_commands.json")

            # emit compile commands database for the current path into a temp file
            update_compilation_database(
                compile_commands, buck_mode, os.getcwd(), target_query, overwrite=True
            )

            print(emphasis_color("querying all target inputs"))
            # emit query for all the input files for the targets we generated above:
            target_files = buck_query([buck_mode], f"inputs({target_query})")

            # filter the target files,
            tidy_files = build_file_list(target_files, specified_files)

            if len(tidy_files) == 0:
                print(error_color("no files were found that were not ignored"))
                sys.exit(1)

            result = invoke_tidy(
                database_directory,
                tidy_files,
                fix,
                fix_errors,
                errors_only,
                use_runner,
                export_fixes,
            )
            if result == 0:
                print(success_color("success - completed with no errors!"))
            else:
                print(error_color("error: exiting with errors"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="apply clang format to folder")
    parser.add_argument(
        "--target-directory",
        type=str,
        help="directory to which clang tidy should be applied",
        default=os.getcwd(),
    )
    parser.add_argument(
        "--target-query",
        type=str,
        help="query to find targets to tidy",
        default=queries.buildable_targets,
    )
    parser.add_argument(
        "--mode",
        type=str,
        help="buck mode to use for verification",
        default=default_buck_mode,
    )
    parser.add_argument(
        "--fix",
        help="Apply suggested fixes. Without -fix-errors clang-tidy will bail out if any compilation errors were found",
        action="store_const",
        const=True,
    )
    parser.add_argument(
        "--use-runner",
        help="use the run-clang-tidy parallel runner script",
        action="store_const",
        const=True,
    )
    parser.add_argument(
        "--fix-errors",
        help="Apply suggested fixes even if compilation errors were found. If compiler errors have attached fix - its, clang - tidy will apply them as well.",
        action="store_const",
        const=True,
    )
    parser.add_argument(
        "--errors-only",
        help="Just show clang build issues.",
        action="store_const",
        const=True,
    )
    parser.add_argument(
        "--files",
        type=str,
        nargs="+",
        help="run tidy against specific files - try to guess (intuit?) what build target it belongs to.",
        default=None,
    )
    parser.add_argument(
        "--loop",
        help="Loop until success - warning, this is rarely actually useful.",
        action="store_const",
        const=True,
    )
    parser.add_argument(
        "--export-fixes",
        type=str,
        help="YAML file to store suggested fixes in. The stored fixes can be applied to the input source.",
        default=None,
    )
    parser.add_argument(
        "--diff",
        help="Run the tidy command on all the files in my current diff under the specified directory.  Not compatile with --files",
        action="store_const",
        const=True,
    )

    args = parser.parse_args()

    while True:
        result = run_clang_tidy(
            args.target_directory,
            args.target_query,
            args.mode,
            args.use_runner,
            args.fix,
            args.fix_errors,
            args.errors_only,
            args.files,
            args.export_fixes,
            args.diff,
        )

        if not args.loop or result == 0:
            break

    sys.exit(result)

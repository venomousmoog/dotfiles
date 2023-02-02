#!/usr/bin/env python3

import argparse
import json
import os
import platform
import subprocess
import sys

import queries
from common_tools import (change_cwd, exec_lines, get_buck_root, pretty_targets, print_trimmed, print_command, temporary_filename, get_default_mode)

default_mode = get_default_mode()

vs_path = "c:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\Professional\\Common7\\IDE\\devenv.exe"
windbg_path = os.path.join(
    get_buck_root(), "third-party/toolchains/windows10sdk/Debuggers/x64/windbg.exe"
)

default_target = queries.all_targets


def filter_mode(args):
    return filter(lambda x: x.startswith("@"), args), filter(
        lambda x: not x.startswith("@"), args
    )


def invoke_buck(args, report=True):
    with temporary_filename() as report_file:
        cmd = ["buck"] + args
        if report:
            cmd.extend(["--build-report", report_file])
        print_command(cmd)
        result = subprocess.call(cmd)
        if result != 0:
            print("buck exited with errors")
            sys.exit(result)

        if report:
            with open(report_file, "r") as r:
                build_database = json.load(r)

            return build_database


# TODO - we should offer an option to exit at prompt or suppress input
def prompt_target(str, results):
    list = []
    for i, j in enumerate(results):
        print(i, j)
        list.append(j)
    if len(list) > 1:
        num = int(input(str))
        return list[num]
    elif len(list) == 1:
        return list[0]
    else:
        print("no target found")
        sys.exit(1)


def buck_build(modes, target, rest):
    return invoke_buck(["build"] + modes + [target] + rest)


# pass thru args after a --
def get_passthru_args(rest):
    if "--" in rest:
        index = rest.index("--")
        return (rest[0:index], rest[index + 1 :])
    elif "//" in rest:
        index = rest.index("//")
        return (rest[0:index], rest[index + 1 :])
    else:
        return (rest, [])


# if there's another --, the we get debugger args, otherwise, exe
def get_debug_args(rest):
    if "--" in rest:
        index = rest.index("--")
        return (rest[0:index], rest[index + 1 :])
    else:
        return ([], rest)


# find an output in a given target spec
def find_output(target):
    if "output" in target:
        return target["output"]
    elif "outputs" in target:
        return target["outputs"]["DEFAULT"][0]
    else:
        return None


def find_output_or_fail(target):
    output = find_output(target)
    if output == None:
        print(f"can't find output in {target}")
        sys.exit(1)


def find_runnable(target, modes, results):
    runnable = find_output(results[target])
    if runnable != None and not runnable.endswith(".par"):
        return [runnable], os.environ

    # if there was no target output, we probably built a command
    # alias - let's try to find the actual target exe and environment:
    cmd = ["buck", "run", "--print-command"] + modes + [target]
    print_command(cmd)
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    result = result.stdout.decode("utf-8")
    result = json.loads(result)
    return result["args"], result["env"]


def buck_run(modes, target, rest):
    buck_rest, debug_rest = get_passthru_args(rest)

    build_database = buck_build(modes, target, buck_rest)
    results = build_database["results"]
    target = prompt_target("choose run target: ", results)
    if results[target]["success"]:
        runnable, env = find_runnable(target, modes, results)
        cmd = [os.path.join(get_buck_root(), runnable[0])] + runnable[1:] + debug_rest
        print_command(cmd)
        return subprocess.call(cmd, env=env)
    return 1


def buck_test(modes, target, rest):
    return invoke_buck(["test"] + modes + [target] + rest)


def buck_targets(modes, target, rest):
    cmd = ["buck", "targets"] + modes + [target] + rest
    return sorted(exec_lines(cmd))


def run_devserver_debugger(binary, env, dbg_params, exe_params):
    # running commands (or debugging them) on a devserver is a bit of tricky business.  See
    # both the description of commands in arvr/tools/build_defs/oxx.bzl around _oxx_runner and _loader,
    # as well as the very useful but also very complex workplace post that can be found here:
    # https://fb.workplace.com/groups/perforce/permalink/2445482942166973/?hc_location=ufi
    #
    # This logic is going to try and emulate, given a binary target, the environment that is
    # created via the _oxx_runner command alias.  That alias does run the binary target, but with a
    # placeholder environment.
    #
    # note that you can set a single test to run in a loop under the debugger like so:
    #   (gdb) set pagination off
    #   (gdb) break exit
    #   Breakpoint 1 at 0xcafef00dbeef: file exit.c, line 99.
    #   (gdb) commands
    #   Type commands for breakpoint(s) 1, one per line.
    #   End with a line saying just "end".
    #   >run
    #   >end
    #   (gdb) run
    cmd = (
        [
            "gdb",
            "-q",  # be much quieter
            "--ex",
            "set confirm off",
            "--ex",
            f"add-symbol-file {binary}",
            "--ex",
            "set confirm on",
        ]
        + dbg_params
        + [
            "--args",
            "/usr/local/fbcode/platform009/lib/ld-linux-x86-64.so.2",
            "--library-path",
            "$ORIGIN:/usr/local/fbcode/platform009/lib:/usr/lib64",
            binary,
        ]
        + exe_params
    )
    print_command(cmd)
    # for linux devservers we're going to keep things interactive and wait for exit:
    return subprocess.call(cmd, env=env)


def run_vs_debugger(binary, env, dbg_params, exe_params):
    # If we're on windows we just debug an exe - ideally we'd generate a temporary sln we can
    # find later so it would remember breakpoints and whatnot but we're not that smart yet, and
    # if folks want to get that fancy they can probably use vsgo
    cmd = [vs_path] + dbg_params + ["/debugexe", binary] + exe_params
    print_command(cmd)
    return subprocess.Popen(cmd, env=env)


def run_windbg_debugger(binary, env, dbg_params, exe_params):
    # If we're on windows we just debug an exe - ideally we'd generate a temporary sln we can
    # find later so it would remember breakpoints and whatnot but we're not that smart yet, and
    # if folks want to get that fancy they can probably use vsgo
    cmd = [windbg_path] + dbg_params + [binary] + exe_params
    print_command(cmd)
    return subprocess.Popen(cmd, env=env)


def buck_debug(modes, target, rest):
    buck_rest, debug_rest = get_passthru_args(rest)
    build_database = buck_build(modes, target, buck_rest)
    results = build_database["results"]
    target = prompt_target("choose debug target: ", results)
    if results[target]["success"]:
        runnable, env = find_runnable(target, modes, results)
        exe = os.path.join(get_buck_root(), runnable[0])

        # rest for debugging is a little bit different - if there
        # are commands in rest, they are by default directed to the debuggee.
        # if there are two instances of --, the first set of rest commands go to
        # the debugger, and the rest go to the debuggee.
        #
        # b.py blah blah -- some debuggee commands
        # b.py blah blah -- some debugger commands -- some debuggee commands
        # b.py blah blah -- some debugger commands --
        # b.py blah blah -- -- a debuggee which needs to take a -- as a parameter
        #
        dbg_params, exe_params = get_debug_args(debug_rest)
        if platform.system() == "Linux":
            run_devserver_debugger(exe, env, dbg_params, exe_params + runnable[1:])
        else:
            run_vs_debugger(exe, env, dbg_params, exe_params + runnable[1:])


#      run_windbg_debugger(exe, env, dbg_params, exe_params + runnable[1:])


def buck_query(modes, query, rest=[], quiet=False):
    cmd = ["buck", "query"] + modes + [query] + rest
    return sorted(exec_lines(cmd, quiet=quiet))


def save_buck_query(modes, query, output):
    targets = buck_query(modes, query)
    print(pretty_targets(targets))
    with open(output, "w") as f:
        for target in targets:
            f.write(target + "\n")


def targets(modes, query, rest=[]):
    results = buck_targets(modes, query, rest)
    for t in pretty_targets(results):
        print(t)


def query(modes, query, rest=[]):
    results = buck_query(modes, query, rest)
    for t in results:
        print(t)


def queryq(modes, query, rest=[]):
    results = buck_query(modes, query, rest)
    for t in results:
        print(t)


def buildq(modes, target, rest):
    with temporary_filename() as target_file:
        save_buck_query(modes, target, target_file)
        buck_build(modes, f"@{target_file}", rest)


def runq(modes, target, rest):
    with temporary_filename() as target_file:
        save_buck_query(modes, target, target_file)
        buck_run(modes, f"@{target_file}", rest)


def testq(modes, target, rest):
    with temporary_filename() as target_file:
        save_buck_query(modes, target, target_file)
        buck_test(modes, f"@{target_file}", rest)


def debugq(modes, target, rest):
    with temporary_filename() as target_file:
        save_buck_query(modes, target, target_file)
        buck_debug(modes, f"@{target_file}", rest)


def targetsq(modes, target, rest):
    targets = buck_query(modes, target, rest)
    for t in targets:
        print(t)


# Aliases - just replace anything in the command line that starts with # with this:
aliases = {
    "bb": "bb",
}

# for calling the script directly...
if __name__ == "__main__":
    commands = {
        "build": buck_build,
        "run": buck_run,
        "test": buck_test,
        "debug": buck_debug,
        "query": query,
        "queryq": queryq,
        "targets": targets,
        "buildq": buildq,
        "runq": runq,
        "testq": testq,
        "debugq": debugq,
        "targetsq": targetsq,
    }

    if len(sys.argv) <= 1:
        print(f"usage: b command [@arvr/mode] [target/query] [options]")
        print(f" default mode: {default_mode}")
        print(" commands [{}] ".format(", ".join(commands)))
        sys.exit(0)

    # first, common operations:
    command = sys.argv[1]
    modes, rest = filter_mode(sys.argv[2:])
    rest = list(rest)
    modes = list(modes)

    if len(modes) == 0 and default_mode:
        modes = [default_mode]

    # pick out a target - it should be the next parameter unless
    # the next parameter is an option (--)
    if len(rest) > 0 and not rest[0].startswith("-"):
        target = rest[0]
        rest = rest[1:]
        # if no target with a colon has been specified, assume
        # the caller wants one from the current directory
        if target in aliases:
            target = aliases[target]
        elif not ":" in target and not "..." in target and not command.endswith("q"):
            target = ":" + target
    else:
        if command == "query" or command.endswith("q"):
            target = queries.default_targets
        else:
            target = queries.all_targets

    # invoke the command
    commands.get(command, lambda: "unknown mode")(modes, target, rest)

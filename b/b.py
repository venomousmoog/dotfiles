#!/usr/bin/env python3

import argparse
import json
import os
import platform
import subprocess
import sys

from fnmatch import fnmatch

import queries
import toml

from common_tools import (
    change_cwd,
    exec_lines,
    get_buck_root,
    pretty_targets,
    print_command,
    print_trimmed,
    temporary_filename,
)

# Lazily compute buck_root. Stored in function attribute.
def get_buck_root():
    if not hasattr(get_buck_root, "inner"):
        result = subprocess.run(
            ["buck2", "root"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
        )
        result = result.stdout.decode("utf-8")
        get_buck_root.inner = result.strip()

    return get_buck_root.inner


def get_absolute_buck_root():
    if not hasattr(get_absolute_buck_root, "inner"):
        root = get_buck_root()
        parent = os.path.dirname(root)
        while True:
            try:
                with change_cwd(parent):
                    next = subprocess.run(
                        ["buck2", "root"],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL,
                    )

                next = next.stdout.decode("utf-8").strip()
                if not next:
                    break

                root = next
                parent = os.path.dirname(root)
            except subprocess.CalledProcessError:
                break

        get_absolute_buck_root.inner = root

    return get_absolute_buck_root.inner


def get_cell_root(cell: str):
    if not hasattr(get_cell_root, "cells"):
        cells = {}
        for line in exec_lines(["buck2", "audit", "cell"], quiet=True):
            c, p = line.split(": ", 2)
            cells[c] = p

        get_cell_root.cells = cells

    cells = get_cell_root.cells
    return cells[cell]


def get_target_path(target):
    """return the path to the target relative to the enlistment root"""

    # we need to support:
    # //blah/blah
    # :
    # ...
    # //blah/blah/...
    # //blah/blah:
    # //blah/blah:targ
    # cell//blah/blah:targ

    absolute = False
    cell = ""
    path = target
    if "//" in target:
        cell, path = target.split("//", 2)
        absolute = True

    if path.endswith("..."):
        path = path[:-3]

    if ":" in path:
        path, _ = path.rsplit(":", 2)

    root = get_buck_root()

    if cell:
        root = get_cell_root(cell)

    if absolute:
        return os.path.normpath(os.path.join(root, path)).replace("\\", "/")
    else:
        return os.path.normpath(os.path.abspath(path)).replace("\\", "/")


def get_default_mode():
    if os.getenv("BUCK_MODE"):
        env_mode = os.getenv("BUCK_MODE")
        if env_mode and len(env_mode) > 1:
            return env_mode
        else:
            return None

    return "@auto-dev"


default_mode = get_default_mode()


def get_default_buck():
    if os.getenv("DEFAULT_BUCK"):
        return os.getenv("DEFAULT_BUCK")

    return "buck2"


default_buck = get_default_buck()


def get_target_auto_data(target: str, flavor: str):
    auto_mode_file = get_target_path("fbcode//buck_auto_mode/data/buck_auto_mode.toml")
    modes = toml.load(auto_mode_file)
    target_path = get_target_path(target)
    absolute_buck_root = get_absolute_buck_root()
    target_path = (
        os.path.relpath(target_path, absolute_buck_root).replace("\\", "/") + "/"
    )

    for project in modes["Project"]:
        for pattern in project["paths"]:
            if fnmatch(target_path, pattern):
                platform_section = project.get(platform.system().lower(), None)
                if platform_section:
                    for f in [flavor, "dev", "dbg", "opt", "asan", "tsan"]:
                        if f in platform_section:
                            chosen_mode = ""
                            if isinstance(platform_section[f], list):
                                chosen_mode = platform_section[f][0]
                            else:
                                chosen_mode = platform_section[f]

                            chosen_buck = project["build"]
                            if chosen_buck == "fbcode-contbuild":
                                chosen_buck = "buck2"

                            # now we have to make the chosen mode relative to our local buck root:
                            return (
                                chosen_buck,
                                "@//"
                                + os.path.relpath(
                                    os.path.join(get_absolute_buck_root(), chosen_mode),
                                    get_buck_root(),
                                ),
                            )

                    return (None, None)
    return (None, None)


def get_target_auto_mode(target: str, flavor: str):
    (_, mode) = get_target_auto_data(target, flavor)
    return mode


def get_target_auto_buck(target: str, flavor: str):
    (buck_tool, _) = get_target_auto_data(target, flavor)
    if buck_tool:
        return buck_tool
    else:
        return default_buck


vs_path = "c:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\Professional\\Common7\\IDE\\devenv.exe"
windbg_path = os.path.join(
    get_buck_root(), "third-party/toolchains/windows10sdk/Debuggers/x64/windbg.exe"
)

default_target = queries.all_targets


def filter_mode(args):
    return filter(lambda x: x.startswith("@"), args), filter(
        lambda x: not x.startswith("@"), args
    )


def invoke_buck(tool, args, report=True):
    with temporary_filename() as report_file:
        cmd = [tool] + args
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
    if runnable != None:
        return [runnable], os.environ

    # if there was no target output, we probably built a command
    # alias - let's try to find the actual target exe and environment:
    cmd = ["buck2", "run", "--print-command"] + modes + [target]
    print_command(cmd)
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    result = result.stdout.decode("utf-8")
    result = json.loads(result)
    return result["args"], result["env"]


def buck_run(tool, modes, target, rest):
    buck_rest, debug_rest = get_passthru_args(rest)

    build_database = buck_build(tool, modes, target, buck_rest)
    results = build_database["results"]
    target = prompt_target("choose run target: ", results)
    if results[target]["success"]:
        runnable, env = find_runnable(target, modes, results)
        cmd = (
            [os.path.join(get_absolute_buck_root(), runnable[0])]
            + runnable[1:]
            + debug_rest
        )
        print_command(cmd)
        return subprocess.call(cmd, env=env)
    return 1


def buck_targets(tool, modes, target, rest):
    cmd = ["buck2", "targets"] + modes + [target] + rest
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


def run_vscode_debugger(binary, env, dbg_params, exe_params):
    vscode_launch_template = """
    {{
        "version": "0.2.0",
        "configurations": [
            {{
                "name": "Launch Buck target",
                "type": "fb-lldb",
                "request": "launch",
                "program": "{path}",
                "args": {args},
                "cwd": "{root}",
                "env": [],
                "debuggerRoot": "{root}",
                "sourceMap": [
                    [
                        ".",
                        "{root}"
                    ],
                    [
                        "/home/engshare",
                        "{root}/fbcode"
                    ],
                    [
                        ".",
                        "{root}/.."
                    ],
                    [
                        ".",
                        "{root}/fbcode"
                    ],
                ]
            }},
        ]
    }}
    """
    with open(os.path.join(get_absolute_buck_root(), ".vscode/launch.json"), "w") as f:
        def reslash(str):
            return str.replace("\\", "/")

        output = vscode_launch_template.format(
            path=reslash(binary),
            root=reslash(get_absolute_buck_root()),
            args=json.dumps(exe_params),
        )
        f.write(output)


def save_buck_query(tool, modes, query, output):
    targets = buck_query(tool, modes, query)
    print(pretty_targets(targets))
    with open(output, "w") as f:
        for target in targets:
            f.write(target + "\n")
    # return the first target as an "info" target:
    if targets:
        return targets[0]
    else:
        return None


def buck_build(tool, modes, target, rest):
    return invoke_buck(tool, ["build"] + modes + [target] + rest)


def buck_test(tool, modes, target, rest):
    return invoke_buck(tool, ["test"] + modes + [target] + rest, report=False)


def buck_targets(tool, modes, target, rest):
    cmd = [tool, "targets"] + modes + [target] + rest
    return sorted(exec_lines(cmd))


def buck_install(tool, modes, target, rest):
    return invoke_buck(tool, ["install"] + modes + [target] + rest, report=False)


def buck_debug(tool, modes, target, rest):
    buck_rest, debug_rest = get_passthru_args(rest)
    build_database = buck_build(tool, modes, target, buck_rest)
    results = build_database["results"]
    target = prompt_target("choose debug target: ", results)
    if results[target]["success"]:
        runnable, env = find_runnable(target, modes, results)
        exe = os.path.join(get_absolute_buck_root(), runnable[0])

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
            # run_devserver_debugger(exe, env, dbg_params, exe_params + runnable[1:])
            run_vscode_debugger(exe, env, dbg_params, exe_params + runnable[1:])
        else:
            # run_windbg_debugger(exe, env, dbg_params, exe_params + runnable[1:])
            run_vscode_debugger(exe, env, dbg_params, exe_params + runnable[1:])


def buck_query(modes, query, rest=[], quiet=False):
    cmd = ["buck2", "query"] + modes + [query] + rest
    return sorted(exec_lines(cmd, quiet=quiet))


def targets(tool, modes, query, rest=[]):
    results = buck_targets(tool, modes, query, rest)
    for t in pretty_targets(results):
        print(t)


def query(tool, modes, query, rest=[]):
    results = buck_query(tool, modes, query, rest)
    for t in results:
        print(t)


def queryq(tool, modes, query, rest=[]):
    results = buck_query(tool, modes, query, rest)
    for t in results:
        print(t)


def buildq(tool, modes, target, rest):
    with temporary_filename() as target_file:
        save_buck_query(tool, modes, target, target_file)
        buck_build(tool, modes, f"@{target_file}", rest)


def runq(tool, modes, target, rest):
    with temporary_filename() as target_file:
        save_buck_query(tool, modes, target, target_file)
        buck_run(tool, modes, f"@{target_file}", rest)


def testq(tool, modes, target, rest):
    with temporary_filename() as target_file:
        save_buck_query(tool, modes, target, target_file)
        buck_test(tool, modes, f"@{target_file}", rest)


def debugq(tool, modes, target, rest):
    with temporary_filename() as target_file:
        save_buck_query(tool, modes, target, target_file)
        buck_debug(tool, modes, f"@{target_file}", rest)


def targetsq(tool, modes, target, rest):
    targets = buck_query(tool, modes, target, rest)
    for t in targets:
        print(t)


def resolve_modes(modes, target, rest):
    def resolve_mode(m):
        if m.startswith("@auto-"):
            return get_target_auto_mode(target, m[len("@auto-") :])
        else:
            return m

    return list([i for i in [resolve_mode(m) for m in modes] if i])


def test_modes(tool, modes, target, rest):
    print(f"tool = {tool}")
    print(f"modes = {modes}")
    print(f"target = {target}")
    print(f"rest = {rest}")
    print(f"target_path = {get_target_path(target)}")
    print(f'target_mode = {get_target_auto_mode(target, "dbg")}')
    print(f"current root = {get_buck_root()}")
    print(f"abs root = {get_absolute_buck_root()}")
    print(f"resolve = {resolve_modes(modes, target, rest)}")


# Aliases - just replace anything in the command line that starts with # with this:
aliases = {
    "bb": "bb",
}

# for calling the script directly...
if __name__ == "__main__":
    commands = {
        "build": buck_build,
        "install": buck_install,
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
        "tests": test_modes,
    }

    if len(sys.argv) <= 1:
        print(f"usage: b command [@mode] [target/query] [options]")
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
        if target.startswith("#") and target[1:] in aliases:
            target = aliases[target[1:]]
        elif not ":" in target and not "..." in target and not command.endswith("q"):
            target = ":" + target
    else:
        if command == "query" or command.endswith("q"):
            target = queries.default_targets
        else:
            target = queries.all_targets

    # compute any auto-mode configuration
    modes = resolve_modes(modes, target, rest)
    buck_tool = get_target_auto_buck(target, "dbg")  # any flavor

    # invoke the command
    commands.get(command, lambda: "unknown command")(buck_tool, modes, target, rest)

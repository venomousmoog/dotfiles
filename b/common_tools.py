#!/usr/bin/env python3

import argparse
import contextlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import platform

from typing import List

script_dir = os.path.dirname(os.path.realpath(__file__))

# Lazily compute buck_root. Stored in function attribute.
def get_buck_root():
    if not hasattr(get_buck_root, "inner"):
        result = subprocess.run(
            ["buck", "root"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
        )
        result = result.stdout.decode("utf-8")
        get_buck_root.inner = result.strip()
    return get_buck_root.inner

def get_default_mode():
    if os.getenv("BUCK_MODE"):
        env_mode = os.getenv("BUCK_MODE")
        if len(env_mode) > 1:
            return env_mode
        else:
            return None
    elif platform.system() == "Linux":
        return "@arvr/mode/linux/dev"
    else:
        return "@arvr/mode/win/opt"

@contextlib.contextmanager
def temporary_filename(suffix=None):
    """Context that introduces a temporary file.

    Creates a temporary file, yields its name, and upon context exit, deletes it.
    (In contrast, tempfile.NamedTemporaryFile() provides a 'file' object and
    deletes the file as soon as that file object is closed, so the temporary file
    cannot be safely re-opened by another library or process.)

    Args:
      suffix: desired filename extension (e.g. '.mp4').

    Yields:
      The name of the temporary file.
    """
    import tempfile

    try:
        f = tempfile.NamedTemporaryFile(suffix=suffix, delete=False)
        tmp_name = f.name
        f.close()
        yield tmp_name
    finally:
        os.unlink(tmp_name)


@contextlib.contextmanager
def change_cwd(target_directory):
    curdir = os.getcwd()
    try:
        os.chdir(os.path.join(curdir, target_directory))
        yield
    finally:
        os.chdir(curdir)


# pretty targets should be shortened relative to the current path
# to make them easier to read, but not shortened if copy/paste wouldn't
# work.
def relative_target(target, startpath):
    startpath = os.path.normpath(os.path.abspath(startpath))
    colon_index = target.rfind(":")
    if target.startswith("//") and colon_index >= 0:
        target_path = os.path.normpath(
            os.path.join(get_buck_root(), target[2:colon_index])
        )
        if os.path.commonpath([startpath]) == os.path.commonpath(
            [startpath, target_path]
        ):
            relative_target_path = os.path.relpath(target_path, startpath)
            if relative_target_path == ".":
                relative_target_path = ""
            return relative_target_path.replace("\\", "/") + target[colon_index:]

    return target


def pretty_targets(targets, startpath=os.getcwd()):
    return sorted([relative_target(t, startpath) for t in targets])


# hack to enable console coloring in cmd.exe
enable_color = False


def enable_console_colors():
    global enable_color
    enable_color = sys.stdout.isatty()
    if enable_color:
        subprocess.call("", shell=True)


# error coloring functions - everybody loves colored output
def emphasis_color(str):
    if enable_color:
        return f"\033[97m{str}\033[00m"
    else:
        return str


def error_color(str):
    if enable_color:
        return f"\033[31m{str}\033[00m"
    else:
        return str


def warning_color(str):
    if enable_color:
        return f"\033[33m{str}\033[00m"
    else:
        return str


def success_color(str):
    if enable_color:
        return f"\033[32m{str}\033[00m"
    else:
        return str


def exec_lines(cmd, stop_on_error=True, quiet=False):
    if not quiet:
        print_command(cmd)
    try:
        result = subprocess.check_output(cmd)
    except subprocess.CalledProcessError as exc:
        if stop_on_error:
            print("command failure: ", exc.returncode, exc.output)
            sys.exit(1)
        else:
            return None
    return result.decode("utf8").splitlines()


def exec_cmd(cmd, stop_on_error=True, quiet=False):
    if not quiet:
        print_command(cmd)
    result = subprocess.call(cmd)
    if stop_on_error and result != 0:
        print("exited with errors")
        sys.exit(result)
    return result


def readfile(path):
    with open(path, "r") as f:
        return f.read()


def writefile(path, contents):
    with open(path, "w") as f:
        return f.write(contents)


def filter_extensions(file_lines, extensions):
    filtered = []
    for file in file_lines:
        for extension in extensions:
            if file.endswith(extension):
                filtered.append(file)

    return filtered

class _Colors:
    Black = "30"
    Red = "31"
    Green = "32"
    Yellow = "33"
    Blue = "34"
    Magenta = "35"
    Cyan = "36"
    White = "37"
    BrightBlack = "30;1"
    BrightRed = "31;1"
    BrightGreen = "32;1"
    BrightYellow = "33;1"
    BrightBlue = "34;1"
    BrightMagenta = "35;1"
    BrightCyan = "36;1"
    BrightWhite = "37;1"
    Reset = "00"

def _print_color(color: str, message: str, end = '\n'):
    print(f"\033[{color}m{message}\033[{_Colors.Reset}m", end = end)

def print_command(cmd: List[str]):
    _print_color(_Colors.Green, f"> ", end='')
    _print_color(_Colors.BrightCyan, " ".join([f"\"{s}\"" if ' ' in s else s for s in cmd]))

def print_trimmed(s):
    if sys.stdout.isatty():
        columns, rows = shutil.get_terminal_size(fallback=(80, 24))
    else:
        columns = sys.maxsize

    trimmed = str(s)
    if len(trimmed) > columns:
        trimmed = trimmed[0 : columns - 3] + "..."

    print(trimmed)

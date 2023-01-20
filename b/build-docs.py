#!/usr/bin/env python3

import argparse
import glob
import os
import shutil
import stat
import subprocess

from b import buck_query
from common_tools import change_cwd
from common_tools import filter_extensions
from common_tools import get_buck_root

doc_extensions = ["cpp", "h"]


def remove_tree(path):
    def remove_readonly(func, path, _):
        if os.path.exists(path):
            os.chmod(path, stat.S_IWRITE)
            func(path)

    shutil.rmtree(path, onerror=remove_readonly)


def build_docs():
    with change_cwd(
        os.path.join(get_buck_root(), "arvr/projects/rocktenn/projects/aishell")
    ):
        remove_tree("docs/html")
        remove_tree("docs/xml")
        files = buck_query(
            ["@arvr/mode/win/dev"], "inputs(kind('cxx_binary|cxx_library', ...))"
        )
        documentable_files = filter_extensions(files, doc_extensions)
        with open("docs/aishell-doxygen-inputs.cfg", "w+") as f:
            f.write("INPUT=\\\n")
            for file in documentable_files:
                f.write(
                    "    ./{0} \\\n".format(
                        os.path.relpath(os.path.join(get_buck_root(), file)).replace(
                            "\\", "/"
                        )
                    )
                )

            # extra markdown documentation
            for file in glob.glob("docs/*.md"):
                f.write(f"    {file} \\\n")

        cmd = [
            "../../win32bin/doxygen_1.8.14/doxygen.exe",
            "docs/aishell-doxygen.cfg",
            "-b",
        ]
        return subprocess.call(cmd)


# for calling the script directly...
if __name__ == "__main__":
    build_docs()

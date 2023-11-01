#!/bin/bash

# execute with "source scripts/aliases.sh" to load into the calling shell context
SCRIPTS_ROOT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

alias bb="python3 $SCRIPTS_ROOT/b.py build"
alias br="python3 $SCRIPTS_ROOT/b.py run"
alias bt="python3 $SCRIPTS_ROOT/b.py test"
alias bq="python3 $SCRIPTS_ROOT/b.py query"
alias bd="python3 $SCRIPTS_ROOT/b.py debug"
alias bg="python3 $SCRIPTS_ROOT/b.py targets"
alias bbq="python3 $SCRIPTS_ROOT/b.py buildq "
alias brq="python3 $SCRIPTS_ROOT/b.py runq"
alias btq="python3 $SCRIPTS_ROOT/b.py testq"
alias bdq="python3 $SCRIPTS_ROOT/b.py debugq"
alias bgq="python3 $SCRIPTS_ROOT/b.py targetsq"
alias bi="python3 $SCRIPTS_ROOT/b.py install"
alias b="python3 $SCRIPTS_ROOT/b.py"
alias updb="python3 $SCRIPTS_ROOT/update_compilation_database.py"
alias tidy="python3 $SCRIPTS_ROOT/run_clang_tidy.py"

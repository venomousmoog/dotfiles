@echo off

set SCRIPTS_ROOT=%~dp0

DOSKEY bb=python3 %SCRIPTS_ROOT%\b.py build  $*
DOSKEY br=python3 %SCRIPTS_ROOT%\b.py run $*
DOSKEY bt=python3 %SCRIPTS_ROOT%\b.py test $*
DOSKEY bq=python3 %SCRIPTS_ROOT%\b.py query $*
DOSKEY bd=python3 %SCRIPTS_ROOT%\b.py debug $*
DOSKEY bg=python3 %SCRIPTS_ROOT%\b.py targets $*
DOSKEY bbq=python3 %SCRIPTS_ROOT%\b.py buildq  $*
DOSKEY brq=python3 %SCRIPTS_ROOT%\b.py runq $*
DOSKEY btq=python3 %SCRIPTS_ROOT%\b.py testq $*
DOSKEY bdq=python3 %SCRIPTS_ROOT%\b.py debugq $*
DOSKEY bgq=python3 %SCRIPTS_ROOT%\b.py targetsq $*
DOSKEY bi=python3 %SCRIPTS_ROOT%\b.py install $*
DOSKEY b=python3 %SCRIPTS_ROOT%\b.py $*
DOSKEY updb=python3 %SCRIPTS_ROOT%\update_compilation_database.py $*
DOSKEY tidy=python3 %SCRIPTS_ROOT%\run_clang_tidy.py $*

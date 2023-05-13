# Buck Helper SCripts

## b.py

```b.py``` is a helper script to make it easier to run common buck commands.  There are a few things that this script helps with:

1) Avoid frequent typing tasks (like having to add @arvr/mode/blah).  By default, ```b.py``` will chose ```@arvr/mode/win/cuda10/dev``` on windows, and ```@arvr/mode/linux/dev``` on Linux.
3) Default to a build current directory when no target is supplied.  I find it generally useful to be able to build all the available targets in a current directory (which gives us a very short command to rebuild everything).  This logic also allows the user to drop the : in the target specifier (that is a debatable improvement).
4) Add useful commands to build targets based on a query.  Buck doesn't support building based on a query (like ```b.py buildq "kind('cxx_binary', ...)"```, which we would like to have build all the cxx_binary targets recursively from the current directory.  This currently has some useful defaults that can build based on a query across targets that match the target platform.
5) Add useful commands to make it easy to invoke a debugger in the same way buck run or buck test is invoked.  ```b.py debug :target``` will invoke a debugger - the debugger is not currently configurable, it uses VS2019 on windows and gdb on a devserver, but it does support the magic incantation to make sure that a proper GDB library path is set up for debugging.
6) Prompt if there's more than one valid target for ```b.py``` run or ```b.py debug```.

b.py was originally build for windows, and also runs on a devserver.

### Modes

If there is a mode specified on the command line, the tool will use that, otherwise it will look in the environment for BUCK_MODE, and if it doesn't find that, it will use the mode `@auto-dev`.

Modes beginning with `@auto-` are special - when they exist, b.py will find the buck_auto_modes file and load the appropriate auto mode for the current targets, using anything after the - as the flavor
selector - so for example, `@auto-dbg` will prefer a `dbg` flavor if one exists, otherwise it will search in the order `dbg`, `dev`, `opt`.

### Examples

```
usage: b command [@mode] [target/query] [options]
 default mode: @auto-dbg
 commands [build, run, test, debug, query, queryq, targets, buildq, runq, testq, debugq, targetsq]
```

```python3 b.py build``` - build all targets recursively (defaults to ```...``` target) with default mode.

```python3 b.py test``` - test all targets recursively (defaults to ```...``` target) with default mode.

```python3 b.py debug target``` - invokes a debugger on the binary output of the ```:target``` target with default mode.

My most frequent usage during development is to just use ```bb``` (from the aliases below) in the directory I'm currently working in.

### Aliases

In ```aliases.cmd``` (for Windows) and ```aliases.sh``` (for Linux) are some nice default aliases to make invoking b.py easier.  In no particular order, they are:

|alias|command|
|-----|-------|
|b|python3 b.py [rest]|
|bb|python3 b.py build [rest]|
|br|python3 b.py run [rest]|
|bt|python3 b.py test [rest]|
|bq|python3 b.py query [rest]|
|bd|python3 b.py debug [rest]|
|bg|python3 b.py targets [rest]|
|bbq|python3 b.py buildq [rest]|
|brq|python3 b.py runq [rest]|

#!/bin/bash

mkdir /tmp/tmux-shared
tmux -S /tmp/tmux-shared/shared new-session -d -s auto
chmod 777 /tmp/tmux-shared/shared

#!/bin/bash

mkdir /tmp/tmux-shared
tmux new-session -S /tmp/tmux-shared/shared -d -s auto
chmod 777 /tmp/tmux-shared/shared

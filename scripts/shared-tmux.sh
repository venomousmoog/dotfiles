#!/bin/bash
tmux -S /tmp/tmux-shared/shared kill-server
sleep 1
mkdir /tmp/tmux-shared
tmux -S /tmp/tmux-shared/shared new-session -d -s auto
tmux -S /tmp/tmux-shared/shared set-option -g default-command bash
chmod 777 /tmp/tmux-shared/shared

#!/bin/sh
claude_bin=/home/ksc/.local/bin/claude
claude_log=/home/ksc/KscTool/scripts/init.log

timestamp=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$timestamp] Claude Code Start ... " >> $claude_log
$claude_bin -p 'OK only?' >> $claude_log 2>&1

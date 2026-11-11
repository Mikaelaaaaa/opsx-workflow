#!/usr/bin/env bash
# eval 1：#88，Stop 閘門在 subagent 做 sub-change 時放行。用法：setup.sh <dest>
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"
build 8389924 "${1:?usage: setup.sh <dest>}" fix/stop-gate-subagent/dev

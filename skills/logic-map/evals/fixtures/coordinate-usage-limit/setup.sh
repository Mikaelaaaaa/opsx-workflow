#!/usr/bin/env bash
# eval 3：#111，協調者在用量上限時暫停派工、限制同時在跑的卡數。用法：setup.sh <dest>
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"
build 6312881 "${1:?usage: setup.sh <dest>}" fix/coordinate-usage-limit/dev

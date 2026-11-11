#!/usr/bin/env bash
# eval 2：#104，gate 標題縮成 slug、answer 用標題第一個字比對。用法：setup.sh <dest>
source "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"
build 24b2c40 "${1:?usage: setup.sh <dest>}" fix/gate-title-slug/dev

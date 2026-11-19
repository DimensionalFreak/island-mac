#!/bin/bash
# Sends one test message to the running Island, the same way another Mac app would.
# Usage: ./send-test-message.sh "Title" "Body"
TITLE="${1:-Hello from Terminal}"
BODY="${2:-Sent with send-test-message.sh}"
printf '{"version":1,"id":"terminal-test","source":"test","kind":"alert","title":"%s","body":"%s","duration":6}\n' "$TITLE" "$BODY" \
  | nc -U -w 1 "$HOME/Library/Application Support/Island/island.sock"

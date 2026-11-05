#!/bin/zsh
cd "${0:A:h}"
node_bin=$(command -v node || true)
if [[ -z "$node_bin" && -x /opt/homebrew/bin/node ]]; then node_bin=/opt/homebrew/bin/node; fi
if [[ -z "$node_bin" && -x /usr/local/bin/node ]]; then node_bin=/usr/local/bin/node; fi
"$node_bin" host/launch.cjs stop

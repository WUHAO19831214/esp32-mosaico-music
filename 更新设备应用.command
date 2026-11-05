#!/bin/zsh
cd "${0:A:h}"
/opt/homebrew/bin/python3.12 host/device.py upload && /opt/homebrew/bin/python3.12 host/device.py publish

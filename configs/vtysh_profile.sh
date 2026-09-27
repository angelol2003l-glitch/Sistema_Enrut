#!/bin/sh
# Auto-ingreso a vtysh en terminales interactivas (Extension Containerlab "Shell")
if [ -t 0 ] && [ "$TERM" != "dumb" ] && [ -z "$VTYSH_LOADED" ]; then
    export VTYSH_LOADED=1
    vtysh
fi

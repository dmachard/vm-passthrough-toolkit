#!/bin/bash

## Load the config file
CONFIG_FILE="/etc/passthrough/config.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

echo "Deallocating hugepages..." >> "$LOGFILE"
echo 0 > /proc/sys/vm/nr_hugepages
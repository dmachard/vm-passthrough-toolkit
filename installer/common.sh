#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="${LOG_FILE:-/tmp/passthrough_setup.log}"

log()     { echo -e "${2:-$NC}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"; }
error()   { log "ERROR:   $1" "$RED";   exit 1; }
warning() { log "WARNING: $1" "$YELLOW"; }
success() { log "SUCCESS: $1" "$GREEN"; }
info()    { log "INFO:    $1" "$BLUE";  }
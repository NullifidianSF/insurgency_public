#!/bin/bash

# At 05:00, 07:00, 09:00 it will try, but at most one of those will actually restart the server.
# crontab -e
# 0 5,7,9 * * * /home/USERNAME/empty_restart.sh >/dev/null 2>&1

### CONFIG – CHANGE THIS FOR EACH SERVER #########################

INS_USER="USERNAME"   # <--- change this to your LGSM user, e.g. user2, user3, etc.

##################################################################

HOME_DIR="/home/${INS_USER}"
SERVER_DIR="${HOME_DIR}/serverfiles/insurgency"
SM_DATA_DIR="${SERVER_DIR}/addons/sourcemod/data"

FLAG="${SM_DATA_DIR}/bm_server_empty.txt"
STAMP="${HOME_DIR}/empty_restart_last"
INS_CMD="${HOME_DIR}/insserver"   # LGSM script

TODAY="$(date +%F)"  # e.g. 2025-12-07

# If we've already restarted today, do nothing
if [ -f "$STAMP" ] && grep -qx "$TODAY" "$STAMP"; then
	exit 0
fi

# Only restart if flag file exists AND contains exactly "1"
if [ -f "$FLAG" ] && grep -qx "1" "$FLAG"; then
	echo "$TODAY" > "$STAMP"
	"$INS_CMD" restart
fi

#!/bin/bash

FLAG="/home/USERNAME/serverfiles/insurgency/addons/sourcemod/data/bm_server_empty.txt"

# Only restart if flag file exists AND contains exactly "1"
if [ -f "$FLAG" ] && grep -qx "1" "$FLAG"; then
	/home/USERNAME/insserver restart
fi

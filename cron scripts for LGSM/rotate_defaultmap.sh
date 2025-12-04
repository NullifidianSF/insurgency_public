#!/bin/bash
set -e

# Path to your LGSM insserver.cfg for THIS server
CFG="/home/USERNAME/lgsm/config-lgsm/insserver/insserver.cfg"
TMP="${CFG}.tmp"

# Path to your coop_custom.txt mapcycle
MAPCYCLE="/home/USERNAME/serverfiles/insurgency/coop_custom.txt"

# Global array for usable maps
MAPS=()

read_mapcycle() {
	local file="$MAPCYCLE"
	local line trimmed no_comment

	MAPS=()

	if [ ! -f "$file" ]; then
		echo "Mapcycle file not found: $file" >&2
		return 1
	fi

	while IFS= read -r line; do
		# Trim leading spaces
		trimmed="${line#"${line%%[![:space:]]*}"}"

		# Skip empty lines
		[ -z "$trimmed" ] && continue

		# Skip lines where first non-space char is a comment marker
		case "$trimmed" in
			\#*|\;*|//*) continue ;;
		esac

		# Strip inline // comments (map names won't contain "//")
		no_comment="${trimmed%%//*}"
		# Trim trailing spaces from no_comment
		no_comment="${no_comment%"${no_comment##*[![:space:]]}"}"

		[ -z "$no_comment" ] && continue

		# At this point no_comment should look like:
		#   "ministry_coop checkpoint"
		#   "ins_desert_atrocity_a1 checkpoint"
		MAPS+=("$no_comment")
	done < "$file"

	if [ ${#MAPS[@]} -eq 0 ]; then
		echo "No usable maps found in $file" >&2
		return 1
	fi
}

# ---- pick a random map from mapcycle ----

read_mapcycle

NUM=${#MAPS[@]}
IDX=$(( RANDOM % NUM ))
CHOICE=${MAPS[$IDX]}

echo "[$(date)] Picking new defaultmap from mapcycle: \"$CHOICE\""

# Replace the defaultmap line in a safe way
awk -v new="defaultmap=\"$CHOICE\"" '
BEGIN {done=0}
{
	if (!done && $0 ~ /^defaultmap="/) {
		print new
		done=1
	} else {
		print
	}
}
END {
	if (!done) {
		# no defaultmap line found, append one
		print new
	}
}
' "$CFG" > "$TMP" && mv "$TMP" "$CFG"

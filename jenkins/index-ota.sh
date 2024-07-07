#!/bin/bash

BASEDIR="$1"
WWWDIR="$2"
BASEURL="$3"
INDEX_DEVICE="$4"

if [ -z "$BASEDIR" ] || [ -z "$WWWDIR" ] || [ -z "$BASEURL" ]; then
	echo "Usage: $0 <basedir> <wwwdir> <baseurl> [device]"
	exit 1
fi

function get_metadata_value() {
	local METADATA_LOCAL="$1"
	local KEY="$2"
	echo "$METADATA_LOCAL" | grep "$KEY=" | cut -f2- -d '='
}

echo "" > transaction.sql

find "$BASEDIR" -name *.zip -or -name *.sha256 -mtime +50 -delete -print
find "$BASEDIR" -empty -type d -delete -print

if [ ! -z "$INDEX_DEVICE" ]; then
	echo "DELETE FROM leaf_ota WHERE device = \"$INDEX_DEVICE\";" > transaction.sql
else
	echo "DELETE FROM leaf_ota;" > transaction.sql
fi
for OTA in $(find "$BASEDIR" -name *.zip); do
	echo "$OTA"
	[ ! -f "$OTA".sha256 ] && sha256sum "$OTA" > "$OTA".sha256

	METADATA=$(unzip -p - "$OTA" META-INF/com/android/metadata 2>/dev/null)
	if [ ! -z "$METADATA" ]; then
		DEVICE=$(get_metadata_value "$METADATA" "pre-device")
		DATETIME=$(get_metadata_value "$METADATA" "post-timestamp")
		INCREMENTAL=$(get_metadata_value "$METADATA" "post-build-incremental")
	else # GSI
		DEVICE=$(echo "$OTA" | cut -f5 -d '-')
		DATETIME=$(date -r "$OTA" +%s)
		INCREMENTAL=$(echo "$OTA" | cut -f3 -d '-')
	fi
	FILENAME=$(basename "$OTA")
	ID=$(cat "$OTA".sha256 | cut -f1 -d ' ')
	ROMTYPE="OFFICIAL"
	SIZE=$(du -b "$OTA" | cut -f1)
	URL=$(echo "$OTA" | sed "s|$BASEDIR|$BASEURL|g")
	VERSION=$(echo "$OTA" | cut -f2 -d '-')
	INCREMENTAL=$(get_metadata_value "$METADATA" "post-build-incremental")
	INCREMENTAL_BASE=$(get_metadata_value "$METADATA" "pre-build-incremental")
	if [ -z "$INCREMENTAL_BASE" ]; then
		FLAVOR=$(echo "$OTA" | cut -f4 -d '-')
	else
		FLAVOR=$(echo "$OTA" | cut -f6 -d '-')
	fi
	UPGRADE=$(cat "$WWWDIR/content/devices/$DEVICE.yml" | grep "format_on_upgrade:" | cut -f2 -d ':' | xargs)

	echo "INSERT INTO leaf_ota(device, datetime, filename, id, romtype, size, url, version, " \
		"flavor, incremental, incremental_base, upgrade) VALUES (\"$DEVICE\", \"$DATETIME\", " \
		"\"$FILENAME\", \"$ID\", \"$ROMTYPE\", \"$SIZE\", \"$URL\", \"$VERSION\", " \
		"\"$FLAVOR\", \"$INCREMENTAL\", \"$INCREMENTAL_BASE\", \"$UPGRADE\");" >> transaction.sql
done

echo "UPDATE leaf_ota SET incremental_base = NULL WHERE incremental_base = '';" >> transaction.sql
cat transaction.sql | mariadb -u leaf -pleaf -D "leaf_ota"
rm transaction.sql

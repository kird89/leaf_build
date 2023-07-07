#!/bin/bash

set -e

if [ "$JENKINS_RELEASETYPE" != "stable" ]; then
	RELEASE_DIR="$JENKINS_RELEASETYPE/"
	LEAF_EXTRAVERSION="-$JENKINS_RELEASETYPE"
fi

LEAF_FLAVORS=(VANILLA GMS microG)
TARGET_FILES_DIR="/var/lib/jenkins/leaf/target-files/$RELEASE_DIR$JENKINS_DEVICE"
MASTER_IP="$(echo $SSH_CLIENT | cut -f1 -d ' ')"
DL_DIR="/var/www/dl.leafos.org/$RELEASE_DIR$JENKINS_DEVICE/$BUILDDATE"
KEY_DIR="/var/lib/jenkins/.android-certs"
AVB_ALGORITHM="SHA256_RSA4096"
OTATOOLS="out/host/linux-x86/bin"
[[ $JENKINS_DEVICE == *_gsi_* ]] && TARGET_IS_GSI=true
export LEAF_BUILDTYPE="OFFICIAL"
export TARGET_RO_FILE_SYSTEM_TYPE="erofs"
export BOARD_EXT4_SHARE_DUP_BLOCKS=true
CCACHE_EXEC=$(which ccache)
export CCACHE_EXEC
[ "$CCACHE_EXEC" ] && export USE_CCACHE=true

if [ "$JENKINS_REPOPICK" ]; then
	TELEGRAM_MESSAGE="Build ${BUILD_DISPLAY_NAME//_/\\_}: [See progress](${BUILD_URL}console)
Repopick: $JENKINS_REPOPICK
Build status:"
else
	TELEGRAM_MESSAGE="Build ${BUILD_DISPLAY_NAME//_/\\_}: [See progress](${BUILD_URL}console)
Build status:"
fi

# Telegram Bot token
source /var/lib/jenkins/leaf/telegram.sh

function telegram() {
	if [ "$JENKINS_TELEGRAM" = true ]; then
		RESULT=$(curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/$1" \
			-d "chat_id=@leafos_ci" \
			-d "parse_mode=Markdown" \
			-d "message_id=$(cat .msgid 2>/dev/null)" \
			-d "text=$2")
		MESSAGE_ID=$(jq '.result.message_id' <<<"$RESULT")
		[[ $MESSAGE_ID =~ ^[0-9]+$ ]] && echo "$MESSAGE_ID" >.msgid
	fi
}

function init() {
	telegram sendMessage "$TELEGRAM_MESSAGE"
}

function sync() {
	THREADS=$(nproc)
	telegram editMessageText "$TELEGRAM_MESSAGE Syncing"
	repo init -u https://git.leafos.org/LeafOS-Project/android -b "leaf-$JENKINS_LEAF_VERSION" --depth=1
	repo forall -c 'git reset --hard; git clean -fdx' >/dev/null || true
	repo sync -j"$THREADS" --jobs-network=$((THREADS < 16 ? THREADS : 16)) --force-sync
	if [ "$JENKINS_REPOPICK" ] && [ "$JENKINS_RELEASETYPE" != stable ]; then
		read -a JENKINS_REPOPICK <<<"$JENKINS_REPOPICK"
		for change in "${JENKINS_REPOPICK[@]}"; do
			if [[ $change =~ ^[0-9]+$ ]]; then
				./vendor/leaf/tools/repopick.py "$change"
			else
				./vendor/leaf/tools/repopick.py -t "$change"
			fi
		done
	fi
}

function target-files() {
	telegram editMessageText "$TELEGRAM_MESSAGE Generating target files"
	source build/envsetup.sh
	fetch_device "$JENKINS_DEVICE"
	if [ "$JENKINS_LUNCH" ]; then
		lunch "${JENKINS_LUNCH}_$JENKINS_DEVICE-$JENKINS_BUILDTYPE"
	else
		lunch "$JENKINS_DEVICE-$JENKINS_BUILDTYPE"
	fi
	for JENKINS_FLAVOR in "${LEAF_FLAVORS[@]}"; do
		unset WITH_GMS
		unset WITH_MICROG
		if [ "$JENKINS_FLAVOR" = "GMS" ]; then
			export WITH_GMS=true
		elif [ "$JENKINS_FLAVOR" = "microG" ]; then
			export WITH_MICROG=true
		fi
		rm -rf "$OUT"
		m -j"$(nproc)" target-files-package otatools
		mv "$OUT/obj/PACKAGING/target_files_intermediates/$TARGET_PRODUCT-target_files-$BUILD_ID.zip" \
			"out/$JENKINS_DEVICE-target_files-$JENKINS_FLAVOR-$BUILD_ID.zip"
	done
}

function sign() {
	telegram editMessageText "$TELEGRAM_MESSAGE Signing build"
	[ "$TARGET_IS_GSI" ] && ALLOW_GSI_DEBUG_SEPOLICY="--allow_gsi_debug_sepolicy"
	mkdir -p "/var/lib/jenkins/leaf/target-files/$RELEASE_DIR$JENKINS_DEVICE"
	for JENKINS_FLAVOR in "${LEAF_FLAVORS[@]}"; do
		"$OTATOOLS/sign_target_files_apks" -o -d "$KEY_DIR" \
			$ALLOW_GSI_DEBUG_SEPOLICY \
			--avb_vbmeta_key "$KEY_DIR/avb.pem" \
			--avb_vbmeta_algorithm "$AVB_ALGORITHM" \
			--extra_apks AdServicesApk.apk="$KEY_DIR/releasekey" \
			--extra_apks Bluetooth.apk="$KEY_DIR/bluetooth" \
			--extra_apks HalfSheetUX.apk="$KEY_DIR/releasekey" \
			--extra_apks OsuLogin.apk="$KEY_DIR/releasekey" \
			--extra_apks SafetyCenterResources.apk="$KEY_DIR/releasekey" \
			--extra_apks ServiceConnectivityResources.apk="$KEY_DIR/releasekey" \
			--extra_apks ServiceUwbResources.apk="$KEY_DIR/releasekey" \
			--extra_apks ServiceWifiResources.apk="$KEY_DIR/releasekey" \
			--extra_apks WifiDialog.apk="$KEY_DIR/releasekey" \
			--extra_apks com.android.adbd.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.adbd.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.adservices.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.adservices.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.apex.cts.shim.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.apex.cts.shim.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.appsearch.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.appsearch.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.art.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.art.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.art.debug.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.art.debug.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.btservices.apex="$KEY_DIR/bluetooth" \
			--extra_apex_payload_key com.android.btservices.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.cellbroadcast.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.cellbroadcast.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.compos.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.compos.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.conscrypt.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.conscrypt.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.extservices.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.extservices.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.i18n.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.i18n.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.ipsec.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.ipsec.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.media.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.media.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.media.swcodec.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.media.swcodec.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.mediaprovider.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.mediaprovider.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.neuralnetworks.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.neuralnetworks.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.ondevicepersonalization.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.ondevicepersonalization.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.os.statsd.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.os.statsd.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.permission.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.permission.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.resolv.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.resolv.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.runtime.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.runtime.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.scheduling.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.scheduling.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.sdkext.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.sdkext.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.tethering.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.tethering.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.tzdata.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.tzdata.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.uwb.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.uwb.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.virt.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.virt.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.vndk.current.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.vndk.current.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.android.wifi.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.android.wifi.apex="$KEY_DIR/avb.pem" \
			--extra_apks com.google.pixel.camera.hal.apex="$KEY_DIR/releasekey" \
			--extra_apex_payload_key com.google.pixel.camera.hal.apex="$KEY_DIR/avb.pem" \
			"out/$JENKINS_DEVICE-target_files-$JENKINS_FLAVOR-$BUILD_ID.zip" \
			"$TARGET_FILES_DIR/$JENKINS_DEVICE-target_files-$JENKINS_FLAVOR-$BUILD_ID-signed.zip"
	done
}

function ota-package-name() {
	OLD_BUILD_ID=$(unzip -p "$TARGET_FILES_DIR/$(cat "$TARGET_FILES_DIR/latest_$JENKINS_FLAVOR" 2>/dev/null)" \
		SYSTEM/build.prop 2>/dev/null | grep ro.build.version.incr | cut -d'=' -f2)
	LEAF_PACKAGE="leaf-$JENKINS_LEAF_VERSION$LEAF_EXTRAVERSION-$BUILD_ID-$JENKINS_FLAVOR-$JENKINS_DEVICE"
	LEAF_INCR_PACKAGE="leaf-$JENKINS_LEAF_VERSION$LEAF_EXTRAVERSION-$OLD_BUILD_ID-incr-$BUILD_ID-$JENKINS_FLAVOR-$JENKINS_DEVICE"
}

function ota-package() {
	telegram editMessageText "$TELEGRAM_MESSAGE Generating OTA package"
	for JENKINS_FLAVOR in "${LEAF_FLAVORS[@]}"; do
		ota-package-name
		if [ "$TARGET_IS_GSI" ]; then
			# Full image package for GSI
			"$OTATOOLS/img_from_target_files" \
				"$TARGET_FILES_DIR/$JENKINS_DEVICE-target_files-$JENKINS_FLAVOR-$BUILD_ID-signed.zip" \
				"$LEAF_PACKAGE-img.zip"

			# Cleanup since there are no incremental packages for GSI
			rm "$TARGET_FILES_DIR/$JENKINS_DEVICE-target_files-$JENKINS_FLAVOR-$BUILD_ID-signed.zip"
			rmdir "$TARGET_FILES_DIR" 2>/dev/null || true
		else
			"$OTATOOLS/ota_from_target_files" -k "$KEY_DIR/releasekey" \
				"$TARGET_FILES_DIR/$JENKINS_DEVICE-target_files-$JENKINS_FLAVOR-$BUILD_ID-signed.zip" \
				"$LEAF_PACKAGE.zip"
			# Incremental OTA
			if [ -f "$TARGET_FILES_DIR/$(cat "$TARGET_FILES_DIR/latest_$JENKINS_FLAVOR" 2>/dev/null)" ]; then
				"$OTATOOLS/ota_from_target_files" -k "$KEY_DIR/releasekey" \
					-i "$TARGET_FILES_DIR/$(cat "$TARGET_FILES_DIR/latest_$JENKINS_FLAVOR")" \
					"$TARGET_FILES_DIR/$JENKINS_DEVICE-target_files-$JENKINS_FLAVOR-$BUILD_ID-signed.zip" \
					"$LEAF_INCR_PACKAGE.zip"
			fi
		fi
	done
}

function upload() {
	telegram editMessageText "$TELEGRAM_MESSAGE Uploading"
	retry_uploading() {
		for ((n = 0; n < 3; n++)); do
			rsync -avP "$1" "jenkins@$MASTER_IP:$DL_DIR" && break
			sleep 30
		done
	}
	ssh jenkins@$MASTER_IP mkdir -p "$DL_DIR"
	for JENKINS_FLAVOR in "${LEAF_FLAVORS[@]}"; do
		ota-package-name
		if [ "$TARGET_IS_GSI" ]; then
			# Full image package for GSI
			retry_uploading "$LEAF_PACKAGE-img.zip"
		else
			retry_uploading "$LEAF_PACKAGE.zip"
			if [ -f "$LEAF_INCR_PACKAGE.zip" ]; then
				retry_uploading "$LEAF_INCR_PACKAGE.zip"
				rm -f "$TARGET_FILES_DIR/$(cat "$TARGET_FILES_DIR/latest_$JENKINS_FLAVOR")"
			fi
			unzip -p "$TARGET_FILES_DIR/$JENKINS_DEVICE-target_files-$JENKINS_FLAVOR-$BUILD_ID-signed.zip" \
				OTA/recovery-two-step.img >"$LEAF_PACKAGE-recovery.img"
			retry_uploading "$LEAF_PACKAGE-recovery.img"
			echo "$JENKINS_DEVICE-target_files-$JENKINS_FLAVOR-$BUILD_ID-signed.zip" >"$TARGET_FILES_DIR/latest_$JENKINS_FLAVOR"
		fi
	done
}

function cleanup() {
	if [ "$BUILD_STATUS" = "SUCCESS" ]; then
		telegram editMessageText "$TELEGRAM_MESSAGE [Completed](https://${DL_DIR/\/var\/www\//})"
	else
		telegram editMessageText "$TELEGRAM_MESSAGE Failed at $STAGE"
	fi

	if [ "$JENKINS_CLEAN" = true ]; then
		rm -rf out
	fi
	rm -f .msgid
	rm -f leaf*.zip
	rm -f leaf*.img
	rm -rf .repo/local_manifests
}

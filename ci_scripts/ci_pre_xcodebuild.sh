#!/bin/sh
# Xcode Cloud pre-build hook: give every archive a build number of its own.
#
# The project pins CURRENT_PROJECT_VERSION = 1 and Info.plist reads CFBundleVersion from it, so
# every archive this repository has ever produced declared itself version 1.0, build 1. The first
# such upload is accepted. Every one after it is rejected at "Prepare Build for App Store
# Connect", because App Store Connect requires CFBundleVersion to be unique within a
# CFBundleShortVersionString and will not take a second build 1 for 1.0.
#
# That failure has a shape worth recognising, because it wasted a day here: it happens *after*
# compile, archive, export and signing have all succeeded, so the build looks entirely healthy
# until the last step, and nothing in the source tree explains it. It also reproduces on every
# push regardless of what changed, which makes it look like whatever was edited most recently.
#
# CI_BUILD_NUMBER is Xcode Cloud's own counter, unique and monotonic per workflow, which is
# exactly the property CFBundleVersion needs. Marketing version is left alone — that is a
# release decision, not a build one.
#
# Runs after ci_post_clone.sh and before xcodebuild. Outside Xcode Cloud the variable is unset
# and the file is untouched, so a local or GitHub Actions build keeps the checked-in value.
set -eu

if [ -z "${CI_BUILD_NUMBER:-}" ]; then
  echo "ci_pre_xcodebuild: not running in Xcode Cloud; leaving CFBundleVersion alone."
  exit 0
fi

PLIST="${CI_PRIMARY_REPOSITORY_PATH:-.}/Etch/Info.plist"

if [ ! -f "$PLIST" ]; then
  echo "ci_pre_xcodebuild: no Info.plist at $PLIST; leaving the build number alone."
  exit 0
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CI_BUILD_NUMBER" "$PLIST"
echo "ci_pre_xcodebuild: CFBundleVersion set to $CI_BUILD_NUMBER."

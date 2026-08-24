#!/bin/sh
# Xcode Cloud post-clone hook: inject commerce tokens into the build.
#
# Reads ETCH_STOREFRONT_TOKEN and ETCH_UPLOAD_TOKEN from the Xcode Cloud workflow's
# environment variables (App Store Connect → Xcode Cloud → workflow → Environment) and
# overwrites the checked-in placeholder CommerceSecrets.generated.swift. If the variables
# aren't set, the placeholder stands and the app builds with ordering disabled — a build
# never fails for a missing secret.
set -eu

SECRETS_FILE="$CI_PRIMARY_REPOSITORY_PATH/Etch/Config/CommerceSecrets.generated.swift"

if [ -z "${ETCH_STOREFRONT_TOKEN:-}" ] || [ -z "${ETCH_UPLOAD_TOKEN:-}" ]; then
  echo "ci_post_clone: commerce tokens not set; building with ordering disabled."
  exit 0
fi

cat > "$SECRETS_FILE" <<SWIFT
import Foundation

/// GENERATED AT BUILD TIME by ci_scripts/ci_post_clone.sh — values from Xcode Cloud
/// environment variables. Never committed.
enum CommerceSecrets {
    static let storefrontToken = "$ETCH_STOREFRONT_TOKEN"
    static let uploadToken = "$ETCH_UPLOAD_TOKEN"
}
SWIFT

echo "ci_post_clone: commerce tokens injected."

#!/bin/bash
#
# Release script for Roxi (hiddify-app)
#
# Usage:
#   .github/release.sh          — interactive, prompts for version
#   .github/release.sh 1.3.9    — non-interactive
#
# What it does:
#   1. Checks for uncommitted changes (blocks release if any)
#   2. Updates version in ALL 5 locations
#   3. Commits everything as "release: version X.Y.Z"
#   4. Tags and pushes to trigger CI
#
set -euo pipefail

SED() { [[ "$OSTYPE" == "darwin"* ]] && sed -i '' "$@" || sed -i "$@"; }

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Step 1: Check for uncommitted changes ──
echo ""
DIRTY_FILES=$(git status --porcelain)
if [ -n "$DIRTY_FILES" ]; then
    echo -e "${RED}✗ Working tree is dirty! Commit or stash these files first:${NC}"
    echo "$DIRTY_FILES"
    echo ""
    echo -e "${YELLOW}Hint: git add -A && git commit -m 'your message'${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Working tree is clean${NC}"

# ── Step 2: Get current version ──
CURRENT_VERSION=$(grep -e "^version:" pubspec.yaml | sed -E 's/version: *([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
CURRENT_BUILD=$(grep -e "^version:" pubspec.yaml | sed -E 's/.*\+([0-9]+)$/\1/')
echo "  Current version: ${CURRENT_VERSION}+${CURRENT_BUILD}"
echo "  Latest tag:      $(git describe --tags --abbrev=0 2>/dev/null || echo 'none')"
echo ""

# ── Step 3: Get new version ──
if [ -n "${1:-}" ]; then
    TAG="$1"
else
    read -p "New version (x.y.z): " TAG
fi

[[ "$TAG" =~ ^[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,2}(\.dev)?$ ]] || {
    echo -e "${RED}✗ Invalid version format. Expected: 1.2.3 or 1.2.3.dev${NC}"
    exit 1
}

IFS="." read -r -a V <<< "$TAG"
VERSION_STR="${V[0]}.${V[1]}.${V[2]}"
BUILD_NUMBER=$(( V[0] * 10000 + V[1] * 100 + V[2] ))

echo ""
echo "  New version: ${VERSION_STR}+${BUILD_NUMBER}"
echo ""

# ── Step 4: Update all version files ──
echo "Updating version files..."

# 4a. pubspec.yaml
SED "s/^version: .*/version: ${VERSION_STR}+${BUILD_NUMBER}/g" pubspec.yaml
echo "  ✓ pubspec.yaml"

# 4b. Windows MSIX
SED "s/^msix_version: .*/msix_version: ${V[0]}.${V[1]}.${V[2]}.0/g" windows/packaging/msix/make_config.yaml
echo "  ✓ make_config.yaml"

# 4c. constants.dart (appVersionCode)
SED "s/static const int appVersionCode = [0-9]*/static const int appVersionCode = ${BUILD_NUMBER}/g" lib/core/model/constants.dart
echo "  ✓ constants.dart"

# 4d. appcast.xml
SED "s/sparkle:version=\"[0-9.]*\"/sparkle:version=\"${VERSION_STR}\"/g" appcast.xml
SED "s/<title>Version [0-9.]*</<title>Version ${VERSION_STR}</g" appcast.xml
echo "  ✓ appcast.xml"

# 4e. iOS project.pbxproj (only the hardcoded CURRENT_PROJECT_VERSION, not $(FLUTTER_BUILD_NUMBER))
if [ -n "$CURRENT_BUILD" ] && [ "$CURRENT_BUILD" != "$BUILD_NUMBER" ]; then
    SED "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD}/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}/g" ios/Runner.xcodeproj/project.pbxproj 2>/dev/null || true
    SED "s/MARKETING_VERSION = ${CURRENT_VERSION}/MARKETING_VERSION = ${VERSION_STR}/g" ios/Runner.xcodeproj/project.pbxproj 2>/dev/null || true
    echo "  ✓ project.pbxproj"
fi

echo ""

# ── Step 5: Verify no version mismatches ──
echo "Verifying version consistency..."
ERRORS=0

PUBSPEC_VER=$(grep -e "^version:" pubspec.yaml | sed -E 's/version: *([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
if [ "$PUBSPEC_VER" != "$VERSION_STR" ]; then
    echo -e "  ${RED}✗ pubspec.yaml: $PUBSPEC_VER (expected $VERSION_STR)${NC}"
    ERRORS=$((ERRORS + 1))
fi

MSIX_VER=$(grep "msix_version:" windows/packaging/msix/make_config.yaml | sed -E 's/.*: *([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
if [ "$MSIX_VER" != "$VERSION_STR" ]; then
    echo -e "  ${RED}✗ make_config.yaml: $MSIX_VER (expected $VERSION_STR)${NC}"
    ERRORS=$((ERRORS + 1))
fi

CONST_VER=$(grep "appVersionCode" lib/core/model/constants.dart | sed -E 's/.*= *([0-9]+).*/\1/')
if [ "$CONST_VER" != "$BUILD_NUMBER" ]; then
    echo -e "  ${RED}✗ constants.dart: $CONST_VER (expected $BUILD_NUMBER)${NC}"
    ERRORS=$((ERRORS + 1))
fi

APPCAST_VER=$(grep "sparkle:version" appcast.xml | head -1 | sed -E 's/.*sparkle:version="([0-9.]+)".*/\1/')
if [ "$APPCAST_VER" != "$VERSION_STR" ]; then
    echo -e "  ${RED}✗ appcast.xml: $APPCAST_VER (expected $VERSION_STR)${NC}"
    ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
    echo -e "${RED}✗ Version mismatch detected! Fix manually.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ All version files consistent${NC}"
echo ""

# ── Step 6: Commit ──
git add -A
git commit -m "release: version ${TAG}"
echo -e "${GREEN}✓ Committed${NC}"

# ── Step 7: Tag and push ──
git push
git tag "v${TAG}"
git push origin "v${TAG}"
echo ""
echo -e "${GREEN}✓ Tag v${TAG} pushed. GitHub Actions will build and release.${NC}"
echo -e "  Track: https://github.com/elongflys-tech/roxi/actions"

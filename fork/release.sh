#!/bin/bash
# Release flow, as in WLTV/FireBro: GitHub Actions (.github/workflows/firetv-fork.yml) builds the pushed HEAD and
# uploads the APKs as the artifact SmartTube-fork-N (the token of a fork cannot create releases). This script, run on
# the dev PC with the local gh login (no token in the repository), waits for that build, downloads the APKs to
# fork/out, publishes them as release fork-N of mefistofelix/SmartTube and as release smarttube-N of
# mefistofelix/firetv-apps, and writes smarttube.json there in the format of SmartTube's own updater
# (appupdatechecker2), which the stable flavor reads (common/src/ststable/res/values/update_urls.xml).
# usage: bash fork/release.sh ["changelog line"]     (after git push, from the repository root, Git Bash)
set -e
REPO=mefistofelix/SmartTube
APPS=mefistofelix/firetv-apps
CHANGELOG="${1:-$(git log -1 --format=%s)}"
git fetch -q origin && git merge-base --is-ancestor HEAD "@{u}" || { echo "push HEAD first (git push)"; exit 2; }
SHA=$(git rev-parse HEAD)
for i in $(seq 1 30); do
  RUN=$(gh run list -R "$REPO" -w firetv-fork.yml -L 20 --json databaseId,headSha -q ".[] | select(.headSha==\"$SHA\") | .databaseId" | head -1)
  [ -n "$RUN" ] && break
  sleep 5
done
[ -n "$RUN" ] || { echo "no Actions run for $SHA"; exit 1; }
gh run watch "$RUN" -R "$REPO" --exit-status > /dev/null || { echo "build failed: gh run view $RUN -R $REPO --log-failed"; exit 1; }
N=$(gh run view "$RUN" -R "$REPO" --json number -q .number)
OUT=fork/out/$N
rm -rf "$OUT"; mkdir -p "$OUT"
gh run download "$RUN" -R "$REPO" -n "SmartTube-fork-$N" -D "$OUT"
CODE=$(grep -o 'versionCode=[0-9]*' "$OUT/version.txt" | cut -d= -f2)
NAME=$(grep -o 'versionName=.*' "$OUT/version.txt" | cut -d= -f2 | tr -d '\r')
[ -n "$CODE" ] && [ -n "$NAME" ] || { echo "no version in $OUT/version.txt"; exit 1; }
APKS=("$OUT/SmartTube-fork-$N-universal.apk" "$OUT/SmartTube-fork-$N-armeabi-v7a.apk" "$OUT/SmartTube-fork-$N-arm64-v8a.apk")
gh release view "fork-$N" -R "$REPO" > /dev/null 2>&1 ||
  gh release create "fork-$N" -R "$REPO" --target "$SHA" --title "SmartTube fork build $N ($NAME)" \
    --notes "$CHANGELOG (versionCode $CODE). Stable flavor org.smarttube.stable, signed with the fork key: uninstall the official SmartTube first." \
    "${APKS[@]}" > /dev/null
gh release view "smarttube-$N" -R "$APPS" > /dev/null 2>&1 ||
  gh release create "smarttube-$N" -R "$APPS" --title "SmartTube fork $NAME" --notes "$CHANGELOG" --latest=false \
    "${APKS[1]}" "${APKS[2]}" > /dev/null
BASE="https://github.com/$APPS/releases/download/smarttube-$N"
BS='\'
ESC=${CHANGELOG//"$BS"/"$BS$BS"}; ESC=${ESC//'"'/"$BS\""}
JSON=$(cat <<JSON
{
    "package": {
        "downloadUrlList": ["$BASE/SmartTube-fork-$N-armeabi-v7a.apk"],
        "downloadUrlList_arm64-v8a": ["$BASE/SmartTube-fork-$N-arm64-v8a.apk"]
    },
    "$NAME": {
        "versionCode": $CODE,
        "changelog": ["$ESC"]
    }
}
JSON
)
OLD=$(gh api "repos/$APPS/contents/smarttube.json" -q .sha 2>/dev/null || true)
gh api -X PUT "repos/$APPS/contents/smarttube.json" -f message="SmartTube fork build $N" \
  -f content="$(printf '%s\n' "$JSON" | base64 -w0)" ${OLD:+-f sha="$OLD"} > /dev/null
echo "release fork-$N: https://github.com/$REPO/releases/tag/fork-$N"
echo "update offered: $NAME ($CODE) $BASE"

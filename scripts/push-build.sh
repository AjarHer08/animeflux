#!/usr/bin/env bash
# Commit + push + jalankan GitHub Actions + unduh APK, semuanya dari terminal.
#
# Pemakaian:
#   scripts/push-build.sh "pesan commit"            # push, build, unduh APK
#   scripts/push-build.sh "pesan commit" v1.1.9     # + buat tag -> GitHub Release otomatis
#
# Prasyarat (sekali saja):  gh auth login   (atau export GH_TOKEN=...)
set -euo pipefail
cd "$(dirname "$0")/.."

MSG="${1:-Perbaikan komik: chapter, filter, pencarian}"
TAG="${2:-}"
WF="build-apk.yml"

command -v gh  >/dev/null || { echo "gh (GitHub CLI) belum terpasang: https://cli.github.com"; exit 1; }
command -v git >/dev/null || { echo "git belum terpasang"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Belum login. Jalankan: gh auth login"; exit 1; }

if [ ! -d .git ]; then
  echo "Folder ini belum repo git. Inisialisasi..."
  git init -b main
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "Belum ada remote 'origin'. Contoh:  git remote add origin https://github.com/USER/animeflux.git"
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git add -A
if git diff --cached --quiet; then
  echo "Tidak ada perubahan untuk di-commit."
else
  git commit -m "$MSG"
fi
git push -u origin "$BRANCH"

if [ -n "$TAG" ]; then
  git tag -f "$TAG"
  git push -f origin "$TAG"
  echo "Tag $TAG di-push -> workflow jalan otomatis & membuat Release."
else
  # push ke main/master sudah memicu workflow; dispatch manual hanya untuk branch lain.
  case "$BRANCH" in
    main|master) ;;
    *) gh workflow run "$WF" --ref "$BRANCH" ;;
  esac
fi

echo "Menunggu workflow mulai..."
sleep 8
RUN_ID="$(gh run list --workflow "$WF" --branch "${TAG:-$BRANCH}" --limit 1 --json databaseId --jq '.[0].databaseId')"
[ -n "$RUN_ID" ] || { echo "Run tidak ditemukan. Cek: gh run list"; exit 1; }

gh run watch "$RUN_ID" --exit-status
mkdir -p dist
gh run download "$RUN_ID" -n animeflux-apk -D dist
echo "Selesai. APK: $(ls dist/*.apk)"

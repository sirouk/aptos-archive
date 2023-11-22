#!/bin/bash

REPO="sirouk/aptos-archive"
API_BASE="https://api.github.com/repos/${REPO}"
LATEST_VERSION=0

contents=$(curl -s "${API_BASE}/git/trees/main?recursive=1" | jq -r '.tree[] | select(.path | test("transaction_[0-9]+-.*/transaction.manifest$")) | .path')

for path in $contents; do
    current_version=$(curl -s "${API_BASE}/contents/${path}" | jq -r '.content' | base64 --decode | gunzip | jq '.last_version')
    if [ "$current_version" -gt "$LATEST_VERSION" ]; then
        LATEST_VERSION=$current_version
    fi
done

echo $LATEST_VERSION
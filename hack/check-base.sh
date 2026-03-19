#!/bin/bash

SYSTEM_NAME="$(uname -s | tr '[:upper:]' '[:lower:]')"
SYSTEM_ARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
LOGCHECK_DIR="$(dirname "$REPO_TOOLS_HACK_DIR")/hack/tools/bin/${SYSTEM_NAME}-${SYSTEM_ARCH}"
sed $REPO_ROOT/.golangci.yaml.in -e "s#<<LOGCHECK_PLUGIN_PATH>>#$LOGCHECK_DIR#g" > $REPO_ROOT/.golangci.yaml
bash "$REPO_TOOLS_HACK_DIR/check.sh" --golangci-lint-config="$REPO_ROOT/.golangci.yaml" $@
bash "$REPO_TOOLS_HACK_DIR/check-skaffold-deps.sh"
bash "$REPO_TOOLS_HACK_DIR/check-charts.sh" ./charts
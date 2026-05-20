# SPDX-FileCopyrightText: SAP SE or an SAP affiliate company and Gardener contributors
#
# SPDX-License-Identifier: Apache-2.0

# VERSION := $(shell cat VERSION)
EFFECTIVE_VERSION ?= $(VERSION)-$(shell git rev-parse --short HEAD)

ifneq ($(strip $(shell git status --porcelain 2>/dev/null)),)
	EFFECTIVE_VERSION := $(EFFECTIVE_VERSION)-dirty
endif

IMAGE_TAG ?= $(EFFECTIVE_VERSION)

# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

REPO_ROOT                         ?= $(shell git rev-parse --show-toplevel)
MAKEFILE_DIR                      ?= $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
REPO_TOOLS_HACK_DIR               ?= $(MAKEFILE_DIR)/hack
LOCAL_SCRIPTS_DIR 				  ?= $(REPO_ROOT)/hack
DIRS                              ?= ./cmd ./pkg ./test
REC_DIRS                          ?= ./cmd/... ./pkg/... ./test/...
TEST_DIRS                         ?= ./cmd/... ./pkg/... ./test/...
DEFAULT_MANIFESTS_DIRS            ?= charts cmd example extensions imagevector pkg plugin test third_party
GENERATE_WHAT                     ?= protobuf codegen manifests logcheck
LOGCHECK_DIR                      := $(MAKEFILE_DIR)/hack/tools/logcheck

#########################################
# Tools                                 #
#########################################

TOOLS_DIR := $(MAKEFILE_DIR)/hack/tools
include $(MAKEFILE_DIR)/hack/tools.mk

## Rules
tools-for-generate: $(CONTROLLER_GEN) $(GOLANGCI_LINT) $(GOIMPORTS) $(YQ) $(OPENAPI_GEN)

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk command is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


# Convention:
# - shared script:   tools/hack/<target>.sh
# - local override:  hack/<target>.sh   (runs instead of shared if exists)
# Usage: $(call run_target,<name>,<args>,<env vars>)
define run_target
@if [ -f "$(LOCAL_SCRIPTS_DIR)/$(1).sh" ]; then \
    echo "Running local override: $(LOCAL_SCRIPTS_DIR)/$(1).sh"; \
    REPO_TOOLS_HACK_DIR=$(REPO_TOOLS_HACK_DIR) REPO_ROOT=$(REPO_ROOT) $(3) $(SHELL) "$(LOCAL_SCRIPTS_DIR)/$(1).sh" $(2); \
else \
    echo "Running shared script: $(REPO_TOOLS_HACK_DIR)/$(1).sh"; \
    REPO_TOOLS_HACK_DIR=$(REPO_TOOLS_HACK_DIR) REPO_ROOT=$(REPO_ROOT) $(3) $(SHELL) "$(REPO_TOOLS_HACK_DIR)/$(1).sh" $(2); \
fi
endef


##@ Development

.PHONY: generate
generate: tools-for-generate
	$(call run_target,generate,,WHAT="$(GENERATE_WHAT)" DEFAULT_MANIFESTS_DIRS="$(DEFAULT_MANIFESTS_DIRS)" TOOLS_BIN_DIR="$(TOOLS_BIN_DIR)" MAX_PARALLEL_WORKERS=1)

.PHONY: format
format: $(GOIMPORTS) $(GOIMPORTSREVISER)
	$(call run_target,format,$(DIRS))

.PHONY: sast
sast: $(GOSEC)
	$(call run_target,sast)

.PHONY: sast-report
sast-report: $(GOSEC)
	$(call run_target,sast,--gosec-report true)

.PHONY: test
test: $(SETUP_ENVTEST)  ## Run tests.
	$(call run_target,test,$(TEST_DIRS))

.PHONY: test-cov
test-cov:
	$(call run_target,test-cover,$(TEST_DIRS))

.PHONY: test-cov-clean
test-cov-clean:
	$(call run_target,test-cover-clean)

.PHONY: check-generate
check-generate: tools-for-generate
	$(call run_target,check-generate,$(REPO_ROOT))

.PHONY: check # TODO: revisit run of make build and build plugin for logcheck, when it's moved out entirely
check: tools-for-generate $(LOGCHECK)
	$(call run_target,check-base,$(REC_DIRS),\
	SKAFFOLD_FILE=$(SKAFFOLD_FILE) \
	SKAFFOLD_BINARY=$(SKAFFOLD_BINARY) \
	SKAFFOLD_CONFIG=$(SKAFFOLD_CONFIG))

# could be added, but unnecessary right now (diff with gardener)
# 	@hack/check-imports.sh ./charts/... ./cmd/... ./extensions/... ./pkg/... ./plugin/... ./test/...
# 	@echo "> Check $(LOGCHECK_DIR)"
# 	@cd $(LOGCHECK_DIR); $(abspath $(GOLANGCI_LINT)) run -c $(REPO_ROOT)/.golangci.yaml --timeout 10m ./...
# 	@cd $(LOGCHECK_DIR); go vet ./...
# 	@cd $(LOGCHECK_DIR); $(abspath $(GOIMPORTS)) -l .
# 	@hack/check-license-header.sh
# 	@hack/check-typos.sh
# 	@hack/check-file-names.sh

.PHONY: clean
clean:
	$(call run_target,clean,$(REC_DIRS))

# wip
.PHONY: tidy
tidy:
	@GO111MODULE=on go mod tidy
	@cd $(LOGCHECK_DIR); go mod tidy
#   @GARDENER_HACK_DIR=$(REPO_TOOLS_HACK_DIR) bash $(HACK_DIR)/update-github-templates.sh

.PHONY: verify
verify: check format test sast

.PHONY: verify-extended
verify-extended: check-generate check format test-cov test-cov-clean sast-report

.PHONY: lint-fix
lint-fix: $(GOLANGCI_LINT) ## Run golangci-lint linter and perform fixes
	$(GOLANGCI_LINT) run --fix

##@ Build

.PHONY: build
build: generate ## Build manager binary.
	go build -o bin/manager cmd/main.go

.PHONY: run
run: generate ## Run a controller from your host.
	go run ./cmd/main.go

# If you wish to build the manager image targeting other platforms you can use the --platform flag.
# (i.e. docker build --platform linux/arm64). However, you must enable docker buildKit for it.
# More info: https://docs.docker.com/develop/develop-images/build_enhancements/
.PHONY: docker-build
docker-build: ## Build docker image with the manager.
	$(CONTAINER_TOOL) build -t ${IMG}:${IMAGE_TAG} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	$(CONTAINER_TOOL) push ${IMG}:${IMAGE_TAG}

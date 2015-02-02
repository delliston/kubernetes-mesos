
# the assumption is that current_dir is something along the lines of:
# 	/home/bob/yourproject/src/github.com/mesosphere/kubernetes-mesos

mkfile_path	:= $(abspath $(lastword $(MAKEFILE_LIST)))
current_dir	:= $(patsubst %/,%,$(dir $(mkfile_path)))
fail		:= ${MAKE} --no-print-directory --quiet -f $(current_dir)/Makefile error

KUBE_GO_PACKAGE	?= github.com/GoogleCloudPlatform/kubernetes
K8SM_GO_PACKAGE	?= github.com/mesosphere/kubernetes-mesos

K8S_CMD		:= \
                   ${KUBE_GO_PACKAGE}/cmd/kubecfg		\
                   ${KUBE_GO_PACKAGE}/cmd/kubectl		\
                   ${KUBE_GO_PACKAGE}/cmd/kube-apiserver	\
                   ${KUBE_GO_PACKAGE}/cmd/kube-proxy

CMD_DIRS := $(shell cd $(current_dir) && find . -type f -name '*.go'|sort|while read f; do echo -E "$$(dirname "$$f")"; done|uniq|cut -f1 -d/ --complement|grep ^cmd/)

FRAMEWORK_CMD	:= ${CMD_DIRS:%=${K8SM_GO_PACKAGE}/%}

LIB_DIRS := $(shell cd $(current_dir) && find . -type f -name '*.go'|sort|while read f; do echo -E "$$(dirname "$$f")"; done|uniq|cut -f1 -d/ --complement|grep -v ^cmd/)

FRAMEWORK_LIB	:= ${LIB_DIRS:%=${K8SM_GO_PACKAGE}/%}

KUBE_GIT_VERSION_FILE := $(current_dir)/.kube-version

SHELL		:= /bin/bash

# a list of upstream projects for which we test the availability of patches
PATCH_SCRIPT	:= $(current_dir)/hack/patches/apply.sh

# TODO: make this something more reasonable
DESTDIR		?= /target

# default build tags
TAGS		?=

.PHONY: all error require-godep framework require-vendor proxy install info bootstrap require-gopath format test patch version test.v

ifneq ($(WITH_MESOS_DIR),)

CFLAGS		+= -I$(WITH_MESOS_DIR)/include
CPPFLAGS	+= -I$(WITH_MESOS_DIR)/include
CXXFLAGS	+= -I$(WITH_MESOS_DIR)/include
LDFLAGS		+= -L$(WITH_MESOS_DIR)/lib

CGO_CFLAGS	+= -I$(WITH_MESOS_DIR)/include
CGO_CPPFLAGS	+= -I$(WITH_MESOS_DIR)/include
CGO_CXXFLAGS	+= -I$(WITH_MESOS_DIR)/include
CGO_LDFLAGS	+= -L$(WITH_MESOS_DIR)/lib

WITH_MESOS_CGO_FLAGS :=  \
	  CGO_CFLAGS="$(CGO_CFLAGS)" \
	  CGO_CPPFLAGS="$(CGO_CPPFLAGS)" \
	  CGO_CXXFLAGS="$(CGO_CXXFLAGS)" \
	  CGO_LDFLAGS="$(CGO_LDFLAGS)"

WITH_MESOS_LD_FLAGS := LD_LIBRARY_PATH=$(WITH_MESOS_DIR)/lib

endif

FRAMEWORK_FLAGS := -v -x -tags '$(TAGS)'

ifneq ($(STATIC),)
FRAMEWORK_FLAGS += --ldflags '-extldflags "-static"'
endif

ifneq ($(WITH_RACE),)
FRAMEWORK_FLAGS += -race
endif

export SHELL
export KUBE_GO_PACKAGE

all: proxy framework

error:
	echo -E "$@: ${MSG}" >&2
	false

require-godep: require-gopath
	@which godep >/dev/null || ${fail} MSG="Missing godep tool, aborting"

require-gopath:
	@test -n "$(GOPATH)" || ${fail} MSG="GOPATH undefined, aborting"

proxy: require-godep $(KUBE_GIT_VERSION_FILE) patch
	go install -ldflags "$$(cat $(KUBE_GIT_VERSION_FILE))" $(K8S_CMD)

require-vendor:

framework: require-godep
	env $(WITH_MESOS_CGO_FLAGS) go install $(FRAMEWORK_FLAGS) $(FRAMEWORK_CMD)

format: require-gopath
	go fmt $(FRAMEWORK_CMD) $(FRAMEWORK_LIB)

test test.v: require-gopath
	test "$@" = "test.v" && args="-test.v" || args=""; \
		env $(WITH_MESOS_CGO_FLAGS) $(WITH_MESOS_LD_FLAGS) go test $$args $(FRAMEWORK_LIB)

install: all
	mkdir -p $(DESTDIR)
	(pkg="$(GOPATH)"; pkg="$${pkg%%:*}"; for x in $(notdir $(K8S_CMD) $(FRAMEWORK_CMD)); do \
	 /bin/cp -vpf -t $(DESTDIR) "$${pkg}"/bin/$$x; done)

info:
	@echo GOPATH=$(GOPATH)
	@echo CGO_CFLAGS="$(CGO_CFLAGS)"
	@echo CGO_CPPFLAGS="$(CGO_CPPFLAGS)"
	@echo CGO_CXXFLAGS="$(CGO_CXXFLAGS)"
	@echo CGO_LDFLAGS="$(CGO_LDFLAGS)"
	@echo RACE_FLAGS=$${WITH_RACE:+-race}
	@echo TAGS=$(TAGS)
	@echo LIB_DIRS=$(LIB_DIRS)
	@echo FRAMEWORK_LIB=$(FRAMEWORK_LIB)
	@echo CMD_DIRS=$(CMD_DIRS)
	@echo FRAMEWORK_CMD=$(FRAMEWORK_CMD)

bootstrap: require-godep
	godep restore

patch: $(PATCH_SCRIPT)
	$(PATCH_SCRIPT)

version: $(KUBE_GIT_VERSION_FILE)

$(KUBE_GIT_VERSION_FILE): require-gopath
	@(pkg="$(GOPATH)"; cd "$${pkg%%:*}/src/$(KUBE_GO_PACKAGE)" && \
	  source $(current_dir)/hack/kube-version.sh && \
	  KUBE_GO_PACKAGE=$(KUBE_GO_PACKAGE) kube::version::ldflags) >$@

$(PATCH_SCRIPT):
	test -x $@ || chmod +x $@

################################################################################
#                              RingBuffer Makefile                             #
################################################################################
PROJECT_NAME := RingBuffer

# Hack for xcode not being able to load the thread sanitizer
CLANG_LIBDIR = $(realpath $(dir $(shell xcrun --find clang))/../lib/clang)
TSAN_DYLD = $(CLANG_LIBDIR)/8.0.0/lib/darwin/libclang_rt.tsan_osx_dynamic.dylib

##################################
#  Swift Compiler and CLI Tools  #
##################################
SWIFT ?= swift
SWIFT_CLI_FLAGS := $(strip $(swift_flags_extra) --color always)
SWIFT_BUILD := $(SWIFT) build $(SWIFT_CLI_FLAGS)
SWIFT_PKG := $(SWIFT) package $(SWIFT_CLI_FLAGS)
ENVIRONMENT := env DYLD_INSERT_LIBRARIES=$(TSAN_DYLD)
SWIFT_TEST := $(ENVIRONMENT) $(SWIFT) test $(SWIFT_CLI_FLAGS)

####################
#  Misc. Programs  #
####################
RM_R := $(RM) -r
JAZZY = /Users/morgan/.rvm/gems/ruby-2.3.1@global/bin/jazzy
OPEN = /usr/bin/open
PKG_CONFIG = /usr/local/bin/pkg-config
SWIFT_LINT = /usr/local/bin/swiftlint
GIT = /usr/local/bin/git

####################
#   DEPENDENCIES   #
####################

####################################
#  Build Config (debug | release)  #
####################################
BUILD_CONFIG := debug
ifeq ($(BUILD_CONFIG), debug)
  BUILD_SUBDIR = build
else ifeq ($(BUILD_CONFIG), release)
  BUILD_SUBDIR = dist
else
  $(error Bad BUILD_CONFIG variable $(BUILD_CONFIG) -- use debug | release)
endif

####################
#  Compiler Flags  #
####################
WARN_FLAGS := -Wextra

OTHER_CFLAGS = $(WARN_FLAGS) $(EXTRA_WARNING_FLAGS) -fcolor-diagnostics

CFLAGS = $(strip $(cflags) $(OTHER_CFLAGS))
LDFLAGS = $(strip $(ldflags) $(OTHER_LDFLAGS))
SWIFTCFLAGS = $(strip $(swiftcflags) $(OTHER_SWIFTCFLAGS))

SPM_CFLAGS = $(patsubst %,-Xcc %,$(CFLAGS))
SPM_LDFLAGS = $(patsubst %,-Xlinker %,$(LDFLAGS))
SPM_SWIFTCFLAGS = $(patsubst %,-Xswiftc %,$(SWIFTCFLAGS))

SPM_FLAGS = $(SPM_CFLAGS) $(SPM_LDFLAGS) $(SPM_SWIFTCFLAGS)

################################
#  Additional Flags for Xcode  #
################################
XCODEPROJ_CFLAGS  =
XCODEPROJ_LDFLAGS = -Xlinker '-framework CoreFoundation'
XCODEPROJ_FLAGS   = $(XCODEPROJ_CFLAGS) $(XCODEPROJ_LDFLAGS)

###########################
#  Documentation Targets  #
###########################
MODULES = RingBuffer
DOC_TARGETS = $(addprefix docs-,$(MODULES))

################################################################################
#                                   TARGETS                                    #
################################################################################
.PHONY: all build build-debug build-release test clean \
  distclean fetch update-deps xcodeproj docs read-docs \
  clean-docs clean-xcode  regenerate-xcode release run

all: build

build: build-$(BUILD_CONFIG)

release: build-release docs

print-%: ; @echo $*=$($*)

docs: $(DOC_TARGETS)
	$(RM_R) build
	$(GIT) add docs
	$(GIT) commit --message "Regenerate Documentation"

$(DOC_TARGETS): $(PROJECT_NAME).xcodeproj | clean-docs
	$(JAZZY) --module $(subst docs-,,$@) \
	  --xcodebuild-arguments -target,$(subst docs-,,$@) \
	  --readme Sources/$(subst docs-,,$@)/README.md \
	  --output docs/$(subst docs-,,$@)

read-docs: docs/index.html
	$(OPEN) ./docs/index.html

$(addprefix build-,debug release):
	$(SWIFT_BUILD) -c $(subst build-,,$@) $(SPM_FLAGS)

test:
	$(SWIFT_TEST) $(SPM_FLAGS)

clean:
	$(RM_R) *.o *.dylib *.a ./{,.}build ./.dist ./docs

clean-xcode:
	$(RM_R) $(PROJECT_NAME).xcodeproj

distclean: clean clean-xcode
	$(RM_R) Packages

fetch:
	$(SWIFT_PKG) fetch

update-deps:
	$(SWIFT_PKG) update

xcodeproj: $(PROJECT_NAME).xcodeproj

regenerate-xcode: clean-xcode $(PROJECT_NAME).xcodeproj

xcopen: $(PROJECT_NAME).xcodeproj
	$(OPEN) $(PROJECT_NAME).xcodeproj

xcreopen: regenerate-xcode xcopen

$(PROJECT_NAME).xcodeproj: Packages
	$(SWIFT_PKG) generate-xcodeproj $(SPM_FLAGS) $(XCODEPROJ_FLAGS)

Packages:
	$(SWIFT_PKG) fetch

lint:
	$(SWIFT_LINT)

lint-autocorrect:
	$(SWIFT_LINT) autocorrect

lint-list-rules:
	$(SWIFT_LINT) rules

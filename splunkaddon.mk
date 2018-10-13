
APPS_DIR      ?= src
OUT_DIR       ?= out
BUILD_DIR     ?= $(OUT_DIR)/work
TEST_RESULTS   = test-reports

PACKAGES_DIR               = $(OUT_DIR)/packages
PACKAGES_SPLUNK_BASE_DIR   = $(PACKAGES_DIR)/splunkbase
PACKAGES_SPLUNK_SEMVER_DIR = $(PACKAGES_DIR)/splunksemver
PACKAGES_SPLUNK_SLIM_DIR   = $(PACKAGES_DIR)/splunkslim

PACKAGE_DIRS = $(PACKAGES_DIR) $(PACKAGES_SPLUNK_BASE_DIR) $(PACKAGES_SPLUNK_SEMVER_DIR) $(PACKAGES_SPLUNK_SLIM_DIR)

MAIN_APP          ?= $(shell ls -1 $(APPS_DIR))
MAIN_APP_DESC     ?= Add on for Splunk
main_app_files     = $(shell find $(APPS_DIR)/$(MAIN_APP) -type f ! -iname "app.manifest" ! -iname "app.conf" ! -iname ".*")
MAIN_APP_OUT       = $(BUILD_DIR)/$(MAIN_APP)

docs_files         = $(shell find docs -type f ! -iname ".*")
README_TEMPLATE   ?= buildtools/templates/README
readme_files       = $(shell find $(README_TEMPLATE) -type f ! -iname ".*")

RELEASE            = $(shell gitversion /showvariable FullSemVer)
BUILD_NUMBER      ?= 0000
COMMIT_ID         ?= $(shell git rev-parse --short HEAD)
BRANCH            ?= $(shell git branch | grep \* | cut -d ' ' -f2)
VERSION            = $(shell gitversion /showvariable FullSemVer)
PACKAGE_SLUG       =
PACKAGE_VERSION    = $(VERSION)
APP_VERSION        = $(VERSION)


ifneq (,$(findstring master, $(BRANCH) ))
	VERSION=$(shell gitversion /showvariable MajorMinorPatch)
	PACKAGE_SLUG=R$(COMMIT_ID)
	PACKAGE_VERSION=$(VERSION)-$(PACKAGE_SLUG)
	APP_VERSION=$(VERSION)$(PACKAGE_SLUG)
endif
ifneq (,$(findstring release, $(BRANCH) ))
	VERSION=$(shell gitversion /showvariable MajorMinorPatch)
	PACKAGE_SLUG=B$(COMMIT_ID)
	PACKAGE_VERSION=$(VERSION)-$(PACKAGE_SLUG)
	APP_VERSION=$(VERSION)$(PACKAGE_SLUG)
endif

COPYRIGHT_DOCKER_IMAGE = splseckit/copyright-header:latest
COPYRIGHT_CMD ?= docker run --rm --volume `pwd`:/usr/src/ $(COPYRIGHT_DOCKER_IMAGE)
COPYRIGHT_SOFTWARE ?= $(MAIN_APP)
COPYRIGHT_SOFTWARE_DESCRIPTION ?= $(MAIN_APP_DESC)
COPYRIGHT_OUTPUT_DIR ?= .
COPYRIGHT_WORD_WRAP ?= 100
COPYRIGHT_PATHS ?= $(APPS_DIR)

SPLUNKBASE    ?= Not Published
REPOSITORY    ?= Private

SPHINXBUILD   = sphinx-build

SPHINXOPTS          =
SPHINXSOURCEDIR     = docs
SPHINXBUILDDIR      = out/docs

EPUB_NAME          ?= README



#.PHONY   = help package clean docs config all_dirs build $(PACKAGE_DIRS) list
.DEFAULT = help

.PHONY: help
help: ## Show this help message.
	@echo 'usage: make [target] ...'
	@echo
	@echo 'targets:'
	@egrep '^(.+)\:\ ##\ (.+)' $(MAKEFILE_LIST) | column -t -c 2 -s ':#' | sed 's/^/  /'

ALL_DIRS = $(OUT_DIR) $(BUILD_DIR) $(TEST_RESULTS) $(PACKAGE_DIRS)

.PHONY: CHECK_ENV
CHECK_ENV: ##Check the environment
CHECK_ENV:
	EXECUTABLES = crudini jq sponge slim splunk-appinspect pandoc sphinx-build
	K := $(foreach exec,$(EXECUTABLES),$(if $(shell which $(exec)),some string,$(error "No $(exec) in PATH")))

.PHONY: clean
clean:
	@rm -rf $(OUT_DIR)
	@rm -rf $(TEST_RESULTS)

# Create all build directories
$(ALL_DIRS):
	@mkdir -p $@


#Copy all source files for main app
$(BUILD_DIR)/%: $(APPS_DIR)/%
	@mkdir -p $(@D)
#	@chmod o-w,g-w,a+X  $(@D)
	cp $< $@
	chmod o-w,g-w,a-x $@

# Copy and update app.conf
$(MAIN_APP_OUT)/default/app.conf: $(ALL_DIRS)\
																	$(patsubst $(APPS_DIR)/%,$(BUILD_DIR)/%,$(main_app_files)) \
																	$(APPS_DIR)/$(MAIN_APP)/default/app.conf
	cp $(APPS_DIR)/$(MAIN_APP)/default/app.conf $(MAIN_APP_OUT)/default/app.conf
	crudini --set $(MAIN_APP_OUT)/default/app.conf launcher version $(APP_VERSION)
	crudini --set $(MAIN_APP_OUT)/default/app.conf launcher description $(MAIN_DESCRIPTION)
	crudini --set $(MAIN_APP_OUT)/default/app.conf install build $(BUILD_NUMBER)
	crudini --set $(MAIN_APP_OUT)/default/app.conf ui label $(MAIN_LABEL)
	chmod o-w,g-w,a-x $@

# Generate readme

#Produced a normalized RST file with substitutions applied
.INTERMEDIATE: out/README/rst/index.rst
out/README/rst/index.rst: $(readme_files)
	@$(SPHINXBUILD) -M rst -d out/README/doctrees $(README_TEMPLATE) out/README/rst $(SPHINXOPTS) -D rst_prolog="$$rst_prolog"



#Convert Normalized rst to mardown format readme for the project
$(MAIN_APP_OUT)/README.md: out/README/rst/index.rst
		pandoc -s -t commonmark -o $(MAIN_APP_OUT)/README.md out/README/rst/index.rst
		chmod o-w,g-w,a-x $@

#Copy and update app.manifest
$(MAIN_APP_OUT)/app.manifest: $(ALL_DIRS)\
															$(patsubst $(APPS_DIR)/%,$(BUILD_DIR)/%,$(main_app_files)) \
															$(MAIN_APP_OUT)/$(LICENSE_FILE) \
															$(MAIN_APP_OUT)/default/app.conf \
															$(APPS_DIR)/$(MAIN_APP)/app.manifest \
															$(MAIN_APP_OUT)/README.md

	cp $(APPS_DIR)/$(MAIN_APP)/app.manifest $(MAIN_APP_OUT)/app.manifest
	slim generate-manifest --update $(MAIN_APP_OUT) | sponge $(MAIN_APP_OUT)/app.manifest
	jq '.info.title="$(MAIN_LABEL)"'  $(MAIN_APP_OUT)/app.manifest | sponge $(MAIN_APP_OUT)/app.manifest
	jq '.info.description="$(MAIN_DESCRIPTION)"'  $(MAIN_APP_OUT)/app.manifest | sponge $(MAIN_APP_OUT)/app.manifest
	jq '.info.license= { "name": "$(COPYRIGHT_LICENSE)", "text": "$(LICENSE_FILE)", "uri": "$(LICENSE_URL)" }'  $(MAIN_APP_OUT)/app.manifest | sponge $(MAIN_APP_OUT)/app.manifest
	chmod o-w,g-w,a-x $@

#Copy and update license file
$(MAIN_APP_OUT)/$(LICENSE_FILE): $(patsubst $(APPS_DIR)/%,$(BUILD_DIR)/%,$(main_app_files)) \
																 $(LICENSE_FILE)
	cp $< $@
	chmod o-w,g-w,a-x $@

.INTERMEDIATE: $(OUT_DIR)/docs/epub/$(EPUB_NAME).epub
$(OUT_DIR)/docs/epub/$(EPUB_NAME).epub: $(docs_files)
	@$(SPHINXBUILD) -M epub "$(SPHINXSOURCEDIR)" "$(SPHINXBUILDDIR)" $(SPHINXOPTS) -D epub_basename=$(EPUB_NAME) -D rst_prolog="$$rst_prolog"

$(MAIN_APP_OUT)/$(EPUB_NAME).epub: $(OUT_DIR)/docs/epub/$(EPUB_NAME).epub
	cp $< $@
	chmod o-w,g-w,a-x $@

$(PACKAGES_SPLUNK_BASE_DIR)/$(MAIN_APP)-$(PACKAGE_VERSION).tar.gz: $(ALL_DIRS) \
				$(patsubst $(APPS_DIR)/%,$(BUILD_DIR)/%,$(main_app_files))\
				$(MAIN_APP_OUT)/$(LICENSE_FILE)\
				$(MAIN_APP_OUT)/app.manifest \
				$(MAIN_APP_OUT)/$(EPUB_NAME).epub \
				$(MAIN_APP_OUT)/README
	slim package -o $(PACKAGES_SPLUNK_BASE_DIR) $(MAIN_APP_OUT)

package: ## Package each app
package: $(PACKAGES_SPLUNK_BASE_DIR)/$(MAIN_APP)-$(PACKAGE_VERSION).tar.gz

test-reports/$(MAIN_APP).xml: $(PACKAGES_SPLUNK_BASE_DIR)/$(MAIN_APP)-$(PACKAGE_VERSION).tar.gz
	splunk-appinspect inspect $(PACKAGES_SPLUNK_BASE_DIR)/$(MAIN_APP)-$(PACKAGE_VERSION).tar.gz --data-format junitxml --output-file test-reports/$(MAIN_APP).xml --excluded-tags manual

package_test: ## Package Test
package_test: test-reports/$(MAIN_APP).xml

docker_package:
	docker run --rm --volume `pwd`:/usr/build -w /usr/build -it splservices/addonbuildimage bash -c "make package_test"
docker_package_test:
	docker run --rm --volume `pwd`:/usr/build -w /usr/build -it splservices/addonbuildimage bash -c "make package_test"

DEPLOY_RUNTIME ?= /kb/runtime
TARGET ?= /kb/deployment

TOP_DIR = ../..
include $(TOP_DIR)/tools/Makefile.common

SERVICE_SPEC = NarrativeJobService.spec      
SERVICE_NAME = NarrativeJobService
SERVICE_PORT = 8001
SERVICE_DIR  = narrative_job_service

ifeq ($(SELF_URL),)
	SELF_URL = http://localhost:$(SERVICE_PORT)
endif

SERVICE_PSGI = $(SERVICE_NAME).psgi

TPAGE_ARGS = --define kb_runas_user=$(SERVICE_USER) --define kb_top=$(TARGET) --define kb_runtime=$(DEPLOY_RUNTIME) --define kb_service_name=$(SERVICE_NAME) --define kb_service_dir=$(SERVICE_DIR) --define kb_service_port=$(SERVICE_PORT) --define kb_psgi=$(SERVICE_PSGI)

TOOLS_DIR = $(TOP_DIR)/tools
WRAP_PERL_TOOL = wrap_perl
WRAP_PERL_SCRIPT = bash $(TOOLS_DIR)/$(WRAP_PERL_TOOL).sh
SRC_PERL = $(wildcard plbin/*.pl)

##########################################
# default targets

.PHONY : compile
compile: initialize

.PHONY : deploy
deploy: deploy-all

.PHONY : deploy-all
deploy-all: deploy-client deploy-service

##########################################
# main targets

.PHONY : deploy-client
deploy-client: deploy-libs deploy-libs-client deploy-scripts

.PHONY : deploy-service
deploy-service: deploy-libs deploy-libs-service deploy-cfg
	mkdir -p $(TARGET)/services/$(SERVICE_DIR)
	$(TPAGE) $(TPAGE_ARGS) service/start_service.tt > $(TARGET)/services/$(SERVICE_DIR)/start_service
	chmod +x $(TARGET)/services/$(SERVICE_DIR)/start_service
	$(TPAGE) $(TPAGE_ARGS) service/stop_service.tt > $(TARGET)/services/$(SERVICE_DIR)/stop_service
	chmod +x $(TARGET)/services/$(SERVICE_DIR)/stop_service
	$(TPAGE) $(TPAGE_ARGS) service/upstart.tt > service/$(SERVICE_NAME).conf
	chmod +x service/$(SERVICE_NAME).conf
	echo "done executing deploy-service target"

##########################################
# deploy-libs targets

.PHONY : deploy-libs-service
deploy-libs-service: build-libs-service deploy-mylibs
	

.PHONY : deploy-libs-client
deploy-libs-client: deploy-mylibs
	

.PHONY : deploy-mylibs
deploy-mylibs: 
	#example: rsync --exclude '*.bak*' -arv MG-RAST-Tools/tools/lib/. $(TARGET)/lib/.

##########################################
# build-libs targets

.PHONY : build-libs-service
build-libs-service:
	mkdir -p lib/Bio/KBase/${SERVICE_NAME}/
	cp impl_code.txt lib/Bio/KBase/${SERVICE_NAME}/${SERVICE_NAME}Impl.pm
	compile_typespec \
		--psgi $(SERVICE_PSGI)  \
		--impl Bio::KBase::$(SERVICE_NAME)::$(SERVICE_NAME)Impl \
		--service Bio::KBase::$(SERVICE_NAME)::Service \
		--client Bio::KBase::$(SERVICE_NAME)::Client \
		--py biokbase/$(SERVICE_NAME)/Client \
		--js javascript/$(SERVICE_NAME)/Client \
		--url $(SELF_URL) \
		$(SERVICE_SPEC) lib

##########################################
# test targets # requires /kb/deployment/user-env.sh to be sourced

.PHONY : test
test: test-client

.PHONY : test-client
test-client:
	<some test script here>; \
	if [ $$? -ne 0 ]; then \
		exit 1; \
	fi
	@echo test-client successful

.PHONY : test-service
test-service:
	$(KB_RUNTIME)/bin/perl test/service-test.pl ; \
	if [ $$? -ne 0 ]; then \
		exit 1; \
	fi
	@echo test-service successful

##########################################

include $(TOP_DIR)/tools/Makefile.common.rules


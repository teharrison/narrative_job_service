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

##########################################
# main targets

default:
	echo "no default make target"

deploy: deploy-all

deploy-all: | build-libs deploy-libs build-service deploy-scripts deploy-cfg

deploy-client: | build-libs deploy-libs deploy-scripts

deploy-service: | build-libs deploy-libs build-service deploy-cfg

##########################################
# helper targets

build-service:
	mkdir -p $(TARGET)/services/$(SERVICE_DIR)
	$(TPAGE) $(TPAGE_ARGS) service/start_service.tt > $(TARGET)/services/$(SERVICE_DIR)/start_service
	chmod +x $(TARGET)/services/$(SERVICE_DIR)/start_service
	$(TPAGE) $(TPAGE_ARGS) service/stop_service.tt > $(TARGET)/services/$(SERVICE_DIR)/stop_service
	chmod +x $(TARGET)/services/$(SERVICE_DIR)/stop_service
	$(TPAGE) $(TPAGE_ARGS) service/upstart.tt > service/$(SERVICE_NAME).conf
	chmod +x service/$(SERVICE_NAME).conf
	echo "done executing deploy-service target"

build-libs:
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

test: test-client

test-client:
	<some test script here>; \
	if [ $$? -ne 0 ]; then \
		exit 1; \
	fi
	@echo test-client successful

test-service:
	$(KB_RUNTIME)/bin/perl test/service-test.pl ; \
	if [ $$? -ne 0 ]; then \
		exit 1; \
	fi
	@echo test-service successful

##########################################

include $(TOP_DIR)/tools/Makefile.common.rules


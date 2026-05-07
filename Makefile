BUILDDIR   := build

MANIFEST   ?= https://github.com/vengaer/zephyr-manifest.git

$(foreach _w,$(file < Dockerfile.in),$(if $(_workdir),,$(if $(findstring |$(_p)|,|WORKDIR|),$(eval _workdir := $(_w)))$(eval _p := $(_w))))

ifndef _workdir
  $(error Could not locate WORKDIR in Dockerfile.in)
endif

_git_head   = $(BUILDDIR)/HEAD
IMAGETAG    = stm32h755/build:$$(cat $(_git_head))

_dirs      += $(BUILDDIR)
_dirs      += $(BUILDDIR)/.cmake

_home      := $(dir $(_workdir))

_volumes   := $(abspath $(CURDIR)):$(_workdir)
_volumes   += $(abspath $(CURDIR))/$(BUILDDIR)/.cmake:$(_home)/.cmake
_volumes   += $(abspath $(HOME))/.ssh:$(_home)/.ssh

docker-run  = docker run --rm $(2) $(foreach _v,$(_volumes),-v$(_v)) --network=host $(IMAGETAG) $(1)

.PHONY: all
all:

$(BUILDDIR)/Dockerfile: Dockerfile.in | $(BUILDDIR)
	sed -e "s/@UID@/$$(id -u)/" -e "s/@GID@/$$(id -g)/" $< > $@

$(_git_head): | $(BUILDDIR)
	git rev-parse @ > $@

.PHONY: docker-image
docker-image: $(BUILDDIR)/.docker.stamp

$(BUILDDIR)/.docker.stamp: $(BUILDDIR)/Dockerfile $(_git_head) | $(BUILDDIR)/.cmake
	docker buildx build -t $(IMAGETAG) --network=host -f $< .
	echo $(IMAGETAG) > $@

.PHONY: venv
venv: .venv/pyvenv.cfg

.venv/pyvenv.cfg: $(BUILDDIR)/.docker.stamp
	$(call docker-run,python3 -m venv .venv)

$(BUILDDIR)/.requirements.stamp: requirements.txt .venv/pyvenv.cfg
	$(call docker-run,python3 -m pip install -r $<)
	$(call docker-run,touch $@)

.PHONY: west-init
west-init: .west/config

.west/config: $(BUILDDIR)/.requirements.stamp
	$(call docker-run,west init -m$(MANIFEST),-ti)

.PHONY: west-update
west-update: $(BUILDDIR)/.west.update.stamp

$(BUILDDIR)/.west.update.stamp: .west/config
	$(call docker-run,west update,-ti)

.PHONY: zephyr-export
zephyr-export: $(BUILDDIR)/.cmake/Zephyr

$(BUILDDIR)/.cmake/Zephyr: $(BUILDDIR)/.west.update.stamp
	$(call docker-run,west zephyr-export)

.PHONY: zephyr-packages
zephyr-packages: $(BUILDDIR)/.zephyr.packages.stamp

$(BUILDDIR)/.zephyr.packages.stamp: $(BUILDDIR)/.cmake/Zephyr
	$(call docker-run,west packages pip --install)

$(_dirs):
	mkdir -p $@

.$(V)SILENT:

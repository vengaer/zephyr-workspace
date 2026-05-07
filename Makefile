BUILDDIR   ?= build

_m4_build  := $(BUILDDIR)/m4
_m7_build  := $(BUILDDIR)/m7

MANIFEST   ?= https://github.com/vengaer/zephyr-manifest
TOOLCHAIN  ?= arm-zephyr-eabi

_manifest  := $(notdir $(MANIFEST))

$(foreach _w,$(file < Dockerfile.in),$(if $(_workdir),,$(if $(findstring |$(_p)|,|WORKDIR|),$(eval _workdir := $(_w)))$(eval _p := $(_w))))

ifndef _workdir
  $(error Could not locate WORKDIR in Dockerfile.in)
endif

_zrpc      := $(_workdir)/zrpc

_git_head   = $(BUILDDIR)/HEAD
IMAGETAG    = stm32h755/build:$$(cat $(_git_head))

_dirs      += $(BUILDDIR)
_dirs      += $(BUILDDIR)/.cmake

_home      := $(dir $(_workdir))

_volumes   := $(abspath $(CURDIR)):$(_workdir)
_volumes   += $(abspath $(CURDIR))/$(BUILDDIR)/.cmake:$(_home)/.cmake
_volumes   += $(abspath $(HOME))/.ssh:$(_home)/.ssh

_pkg_hash  := $(shell echo -n $(_workdir)/zephyr/share/zephyr-package/cmake | md5sum | cut -d' ' -f1)

docker-run  = docker run --rm $(2) $(foreach _v,$(_volumes),-v$(_v)) --network=host $(IMAGETAG) $(1)

.PHONY: all
all: build-m4 build-m7

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

$(BUILDDIR)/.west.update.stamp: .west/config $(wildcard $(_manifest)/west.yml)
	$(call docker-run,west update,-ti)
	$(call docker-run,touch $@)

.PHONY: zephyr-export
zephyr-export: $(BUILDDIR)/.cmake/packages/Zephyr/$(_pkg_hash)

$(BUILDDIR)/.cmake/packages/Zephyr/$(_pkg_hash): $(BUILDDIR)/.west.update.stamp
	$(call docker-run,west zephyr-export)

.PHONY: zephyr-packages
zephyr-packages: $(BUILDDIR)/.zephyr.packages.stamp

$(BUILDDIR)/.zephyr.packages.stamp: $(BUILDDIR)/.cmake/packages/Zephyr/$(_pkg_hash)
	$(call docker-run,west packages pip --install)
	$(call docker-run,touch $@)

.PHONY: zephyr-sdk-install
zephyr-sdk-install: $(BUILDDIR)/.sdk.stamp

$(BUILDDIR)/.sdk.stamp: $(BUILDDIR)/.zephyr.packages.stamp
	$(call docker-run,west sdk install -t $(TOOLCHAIN) -d $(_workdir)/zephyr-sdk)
	$(call docker-run,touch $@)

.PHONY: manifest-requirements
zrpc-requirements: $(BUILDDIR)/.zrpc.requirements.stamp

$(BUILDDIR)/.zrpc.requirements.stamp: $(BUILDDIR)/.sdk.stamp
	$(call docker-run,python3 -m pip install -r $(_zrpc)/requirements.txt)
	$(call docker-run,touch $@)

.PHONY: build-m4
build-m4: $(_m4_build)/zephyr.elf

.PHONY: build-m7
build-m7: $(_m7_build)/zephyr.elf

$(foreach _cpu,m4 m7,$(_$(_cpu)_build)/zephyr.elf): $(BUILDDIR)/.zrpc.requirements.stamp
	$(call docker-run,west build -b nucleo_h755zi_q/stm32h755xx/$(notdir $(patsubst %/,%,$(dir $@))) -d $(dir $@) $(_zrpc)/samples/subsys/rpc/zrpc-virtio)


.PHONY: docker-shell
docker-shell: $(BUILDDIR)/.docker.stamp
	$(call docker-run,bash, -ti)

.PHONY: dsh
dsh: docker-shell

$(_dirs):
	mkdir -p $@

.$(V)SILENT:

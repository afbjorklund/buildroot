################################################################################
#
# ccache
#
################################################################################

CCACHE_VERSION = 4.6.1
CCACHE_SITE = https://github.com/ccache/ccache/releases/download/v$(CCACHE_VERSION)
CCACHE_SOURCE = ccache-$(CCACHE_VERSION).tar.xz
CCACHE_LICENSE = GPL-3.0+, others
CCACHE_LICENSE_FILES = LICENSE.adoc GPL-3.0.txt

# Force ccache to use its internal zstd. The problem is that without
# this, ccache would link against the zstd of the build system, but we
# might build and install a different version of zstd in $(O)/host
# afterwards, which ccache will pick up. This might break if there is
# a version mismatch. A solution would be to add host-zstd has a
# dependency of ccache, but it would require tuning the zstd .mk file
# to use HOSTCC_NOCCACHE as the compiler. Instead, we take the easy
# path: tell ccache to use its internal copy of zstd, so that ccache
# has zero dependency besides the C library.
HOST_CCACHE_CONF_OPTS += -DZSTD_FROM_INTERNET=ON
# Workaround `Fatal error: bad defsym; format is --defsym name=value`
HOST_CCACHE_CONF_OPTS += -DCMAKE_ASM_COMPILER=$(CMAKE_HOST_C_COMPILER)

HOST_CCACHE_ZSTD_VERSION = 1.5.2
HOST_CCACHE_ZSTD_SITE = $(call github,facebook,zstd,v$(HOST_CCACHE_ZSTD_VERSION))
HOST_CCACHE_ZSTD_SOURCE = zstd-$(HOST_CCACHE_ZSTD_VERSION).tar.gz
HOST_CCACHE_EXTRA_DOWNLOADS += $(HOST_CCACHE_ZSTD_SITE)/$(HOST_CCACHE_ZSTD_SOURCE)

CCACHE_LICENSE_FILES += zstd-$(HOST_CCACHE_ZSTD_VERSION)/LICENSE

define HOST_CCACHE_EXTRACT_ZSTD
	cp $(HOST_CCACHE_DL_DIR)/$(HOST_CCACHE_ZSTD_SOURCE) $(HOST_CCACHE_BUILDDIR)
endef
HOST_CCACHE_POST_EXTRACT_HOOKS += HOST_CCACHE_EXTRACT_ZSTD

# Force ccache to use its internal hiredis.
HOST_CCACHE_CONF_OPTS += -DHIREDIS_FROM_INTERNET=ON

HOST_CCACHE_HIREDIS_VERSION = 1.0.2
HOST_CCACHE_HIREDIS_SITE = $(call github,redis,hiredis,v$(HOST_CCACHE_HIREDIS_VERSION))
HOST_CCACHE_HIREDIS_SOURCE = hiredis-$(HOST_CCACHE_HIREDIS_VERSION).tar.gz
HOST_CCACHE_EXTRA_DOWNLOADS += $(HOST_CCACHE_HIREDIS_SITE)/$(HOST_CCACHE_HIREDIS_SOURCE)

CCACHE_LICENSE_FILES += hiredis-$(HOST_CCACHE_HIREDIS_VERSION)/COPYING

define HOST_CCACHE_EXTRACT_HIREDIS
	cp $(HOST_CCACHE_DL_DIR)/$(HOST_CCACHE_HIREDIS_SOURCE) $(HOST_CCACHE_BUILDDIR)
endef
HOST_CCACHE_POST_EXTRACT_HOOKS += HOST_CCACHE_EXTRACT_HIREDIS

# We are ccache, so we can't use ccache
HOST_CCACHE_CONF_ENV = \
	CC="$(HOSTCC_NOCCACHE)" \
	CXX="$(HOSTCXX_NOCCACHE)"
HOST_CCACHE_CONF_OPTS += \
	-UCMAKE_C_COMPILER_LAUNCHER \
	-UCMAKE_CXX_COMPILER_LAUNCHER

# Patch host-ccache as follows:
#  - Use BR_CACHE_DIR instead of CCACHE_DIR, because CCACHE_DIR
#    is already used by autotargets for the ccache package.
#    BR_CACHE_DIR is exported by Makefile based on config option
#    BR2_CCACHE_DIR.
#  - Change hard-coded last-ditch default to match path in .config, to avoid
#    the need to specify BR_CACHE_DIR when invoking ccache directly.
#    CCache replaces home_dir with the home directory of the current user,
#    So rewrite BR_CACHE_DIR to take that into consideration for SDK purpose
HOST_CCACHE_DEFAULT_CCACHE_DIR = $(patsubst \"$(HOME)/%,home_dir + \"/%,\"$(BR_CACHE_DIR)\")

define HOST_CCACHE_PATCH_CONFIGURATION
	sed -i 's,getenv("CCACHE_DIR"),getenv("BR_CACHE_DIR"),' $(@D)/src/Config.cpp
	sed -i 's,home_dir + "/.ccache",$(HOST_CCACHE_DEFAULT_CCACHE_DIR),' $(@D)/src/Config.cpp
	sed -i 's,getenv("XDG_CACHE_HOME"),nullptr,' $(@D)/src/Config.cpp
	sed -i 's,home_dir + "/.cache/ccache",$(HOST_CCACHE_DEFAULT_CCACHE_DIR),' $(@D)/src/Config.cpp
	sed -i 's,getenv("XDG_CONFIG_HOME"),nullptr,' $(@D)/src/Config.cpp
	sed -i 's,home_dir + "/.config/ccache",$(HOST_CCACHE_DEFAULT_CCACHE_DIR),' $(@D)/src/Config.cpp
endef

HOST_CCACHE_POST_PATCH_HOOKS += HOST_CCACHE_PATCH_CONFIGURATION

define HOST_CCACHE_MAKE_CACHE_DIR
	mkdir -p $(BR_CACHE_DIR)
endef

HOST_CCACHE_POST_INSTALL_HOOKS += HOST_CCACHE_MAKE_CACHE_DIR

# Provide capability to do initial ccache setup (e.g. increase default size)
BR_CCACHE_INITIAL_SETUP = $(call qstrip,$(BR2_CCACHE_INITIAL_SETUP))
ifneq ($(BR_CCACHE_INITIAL_SETUP),)
define HOST_CCACHE_DO_INITIAL_SETUP
	@$(call MESSAGE,"Applying initial settings")
	$(CCACHE) $(BR_CCACHE_INITIAL_SETUP)
	$(CCACHE) -s
endef

HOST_CCACHE_POST_INSTALL_HOOKS += HOST_CCACHE_DO_INITIAL_SETUP
endif

$(eval $(host-cmake-package))

ifeq ($(BR2_CCACHE),y)
ccache-stats: host-ccache
	$(Q)$(CCACHE) -s

ccache-options: host-ccache
ifeq ($(CCACHE_OPTIONS),)
	$(Q)echo "Usage: make ccache-options CCACHE_OPTIONS=\"opts\""
	$(Q)echo "where 'opts' corresponds to one or more valid ccache options" \
	"(see ccache help text below)"
	$(Q)echo
endif
	$(Q)$(CCACHE) $(CCACHE_OPTIONS)
endif

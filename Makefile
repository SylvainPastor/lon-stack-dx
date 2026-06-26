# Makefile - thin wrapper around CMake to build the LON Stack DX example
# for the U61 USB dongle (Echelon/EnOcean MIP/U61 FTDI key, e.g. TP/FT-10)
# on a native Linux host (x86-64).
#
# Uses a classic "Unix Makefiles" generator by default (not Ninja). It does
# NOT use the CMake presets (which force Ninja); instead it configures CMake
# directly and overrides the cache variables that select the U61 interface
# and the serial device.
#
# Targets:
#   make           -> configure + build for the U61 dongle (default)
#   make u61       -> same as above
#   make clean     -> remove the CMake build tree
#   make help      -> show this help
#
# Override any variable on the command line, e.g.:
#   make u61 DEV=/dev/ttyUSB1
#   make u61 GEN=Ninja
#   make u61 PLATFORM=PLATFORM_ID_LINUX64_X86_GCC

BUILD_DIR ?= build/u61
GEN       ?= Unix Makefiles
TARGET    ?= lon_stack_example1

# U61 dongle configuration.
IFACE     ?= LON_USB_INTERFACE_U61   # U61 (UMIP) interface, FTDI/ttyUSB
DEV       ?= /dev/ttyUSB0            # serial device of the dongle
LDISC     ?= -1                      # -1 = userspace MIP (no kernel line discipline)

# Optional PLATFORM_ID override (leave empty to use the project default).
PLATFORM  ?=

CMAKE_DEFS := \
	-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
	-DLON_USB_IFACE_TYPE=$(IFACE) \
	-DUSB_DEV_NAME=$(DEV) \
	-DUSB_LINE_DISCIPLINE=$(LDISC)
ifneq ($(PLATFORM),)
CMAKE_DEFS += -DPLATFORM_ID=$(PLATFORM)
endif

.PHONY: u61 clean help
.DEFAULT_GOAL := u61

u61:
	cmake -S . -B $(BUILD_DIR) -G "$(GEN)" $(CMAKE_DEFS)
	cmake --build $(BUILD_DIR) --target $(TARGET) -j
	@echo "Built: $(BUILD_DIR)/$(TARGET)"

clean:
	rm -rf build

help:
	@echo "LON Stack DX - native build for the U61 USB dongle"
	@echo ""
	@echo "Targets:"
	@printf '  %-9s %s\n' "make"  "configure + build the example for U61 (default)"
	@printf '  %-9s %s\n' "u61"   "same as the default target"
	@printf '  %-9s %s\n' "clean" "remove the CMake build tree (build/)"
	@printf '  %-9s %s\n' "help"  "show this help"
	@echo ""
	@echo "Variables (name, default, description):"
	@printf '  %-10s %-25s %s\n' "DEV"      "/dev/ttyUSB0"          "serial device of the dongle"
	@printf '  %-10s %-25s %s\n' "IFACE"    "LON_USB_INTERFACE_U61" "U61 (UMIP) interface type"
	@printf '  %-10s %-25s %s\n' "LDISC"    "-1"                    "userspace MIP (no kernel ldisc)"
	@printf '  %-10s %-25s %s\n' "GEN"      "Unix Makefiles"        "CMake generator (e.g. Ninja)"
	@printf '  %-10s %-25s %s\n' "PLATFORM" "(project default)"     "optional PLATFORM_ID override"
	@echo ""
	@echo "Examples:  make u61 DEV=/dev/ttyUSB1   |   make u61 GEN=Ninja"
	@echo ""
	@echo "Requires cmake (>=3.13) and make. Free /dev/ttyUSB0 (stop lonifd) first."

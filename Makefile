FPC ?= fpc
BUILD_DIR ?= build

.PHONY: all test clean
all:
	mkdir -p $(BUILD_DIR)/units
	$(FPC) -MObjFPC -Scghi -O2 -Fu./src -FU$(BUILD_DIR)/units -FE$(BUILD_DIR) -omdatmod src/mdatmod.lpr

test: all
	$(BUILD_DIR)/mdatmod --self-test

clean:
	rm -rf $(BUILD_DIR)

PLUGIN_WASM_COMPONENT := 1
PLUGIN_WIT_WORLD := markov-junior-plugin
PLUGIN_COMPONENT_NAME := markov_junior_plugin
PLUGIN_WIT_PACKAGE := gams:markov-junior@1.0.0.wasm

MARKOV_JUNIOR_COMP_PATH := $(PLUGIN_DIR)/markov-junior.comp
MARKOV_JUNIOR_ODIN_OBJ := $(BUILD_DIR)/obj/plugins/markov-junior.comp/markov_junior.o.obj

PLUGIN_COMPONENT_SOURCES := \
  $(MARKOV_JUNIOR_COMP_PATH)/component.c \
  $(MARKOV_JUNIOR_ODIN_OBJ)

PLUGIN_COMPONENT_EXTRA_DEPS := \
  $(MARKOV_JUNIOR_COMP_PATH)/plugin.mk \
  $(MARKOV_JUNIOR_COMP_PATH)/component.c \
  $(wildcard $(MARKOV_JUNIOR_COMP_PATH)/markov_junior/*.odin) \
  $(MARKOV_JUNIOR_ODIN_OBJ)

$(BUILD_DIR)/obj/plugins/markov-junior.comp:
	$(Q)mkdir -p $@

$(MARKOV_JUNIOR_ODIN_OBJ): $(wildcard $(MARKOV_JUNIOR_COMP_PATH)/markov_junior/*.odin) | $(BUILD_DIR)/obj/plugins/markov-junior.comp
	$(Q)$(ODIN) build ./$(MARKOV_JUNIOR_COMP_PATH)/markov_junior \
		-target:wasi_wasm32 \
		-build-mode:obj \
		--no-entry-point \
		-o:$(ODIN_OPT) \
		-out:$@

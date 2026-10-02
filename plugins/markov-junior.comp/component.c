#include "markov_junior_plugin.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

extern uint32_t mj_core_run(const uint8_t *model_ptr, uintptr_t model_len,
                            const uint8_t *initial_ptr, uintptr_t initial_len,
                            uint32_t width, uint32_t height, uint32_t depth,
                            uint64_t seed, uint32_t max_steps);
extern const uint8_t *mj_core_output_ptr(void);
extern uintptr_t mj_core_output_len(void);
extern void *mj_core_session_create(const uint8_t *model_ptr, uintptr_t model_len,
                                    const uint8_t *initial_ptr, uintptr_t initial_len,
                                    uint32_t width, uint32_t height, uint32_t depth,
                                    uint64_t seed);
extern uint32_t mj_core_session_step(void *session, uint32_t steps);
extern void mj_core_session_destroy(void *session);

struct exports_gams_markov_junior_markov_junior_session_t {
  void *core_session;
  bool dismissed;
};

static uint32_t read_u32(const uint8_t *p) {
  return ((uint32_t)p[0]) | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
}

static void set_error(markov_junior_plugin_string_t *err) {
  uintptr_t len = mj_core_output_len();
  const uint8_t *ptr = mj_core_output_ptr();
  markov_junior_plugin_string_dup_n(err, (const char *)ptr, (size_t)len);
}

static bool parse_grid_result(exports_gams_markov_junior_markov_junior_grid_t *ret, markov_junior_plugin_string_t *err) {
  uintptr_t len = mj_core_output_len();
  const uint8_t *ptr = mj_core_output_ptr();
  if (len < 32 || ptr[0] != 'M' || ptr[1] != 'J' || ptr[2] != 'R' || ptr[3] != 'O') {
    markov_junior_plugin_string_dup(err, "markov core returned invalid result");
    return false;
  }

  size_t pos = 4;
  ret->width = read_u32(ptr + pos); pos += 4;
  ret->height = read_u32(ptr + pos); pos += 4;
  ret->depth = read_u32(ptr + pos); pos += 4;
  ret->steps_run = read_u32(ptr + pos); pos += 4;
  ret->changed = read_u32(ptr + pos) != 0; pos += 4;
  ret->done = read_u32(ptr + pos) != 0; pos += 4;

  uint32_t values_len = read_u32(ptr + pos); pos += 4;
  if (pos + values_len + 4 > len) {
    markov_junior_plugin_string_dup(err, "markov core result truncated before values");
    return false;
  }
  markov_junior_plugin_string_dup_n(&ret->values, (const char *)(ptr + pos), values_len);
  pos += values_len;

  uint32_t cells_len = read_u32(ptr + pos); pos += 4;
  if (pos + cells_len > len) {
    markov_junior_plugin_string_dup(err, "markov core result truncated before cells");
    return false;
  }
  ret->cells.len = cells_len;
  ret->cells.ptr = NULL;
  if (cells_len > 0) {
    ret->cells.ptr = malloc(cells_len);
    if (!ret->cells.ptr) {
      markov_junior_plugin_string_dup(err, "out of memory copying cells");
      return false;
    }
    memcpy(ret->cells.ptr, ptr + pos, cells_len);
  }
  return true;
}

bool exports_gams_markov_junior_markov_junior_run(
    markov_junior_plugin_list_u8_t *model_ir,
    markov_junior_plugin_list_u8_t *initial_cells,
    exports_gams_markov_junior_markov_junior_run_config_t *config,
    exports_gams_markov_junior_markov_junior_grid_t *ret,
    markov_junior_plugin_string_t *err) {
  uint32_t status = mj_core_run(model_ir->ptr, (uintptr_t)model_ir->len,
                                initial_cells->ptr, (uintptr_t)initial_cells->len,
                                config->width, config->height, config->depth,
                                config->seed, config->max_steps);
  if (status != 0) {
    set_error(err);
    return false;
  }

  return parse_grid_result(ret, err);
}

bool exports_gams_markov_junior_markov_junior_create(
    markov_junior_plugin_list_u8_t *model_ir,
    markov_junior_plugin_list_u8_t *initial_cells,
    exports_gams_markov_junior_markov_junior_create_config_t *config,
    exports_gams_markov_junior_markov_junior_session_state_t *ret,
    markov_junior_plugin_string_t *err) {
  exports_gams_markov_junior_markov_junior_session_t *session = calloc(1, sizeof(*session));
  if (!session) {
    markov_junior_plugin_string_dup(err, "out of memory creating session");
    return false;
  }
  session->core_session = mj_core_session_create(model_ir->ptr, (uintptr_t)model_ir->len,
                                                 initial_cells->ptr, (uintptr_t)initial_cells->len,
                                                 config->width, config->height, config->depth,
                                                 config->seed);
  if (!session->core_session) {
    set_error(err);
    exports_gams_markov_junior_markov_junior_session_destructor(session);
    return false;
  }
  if (!parse_grid_result(&ret->grid, err)) {
    exports_gams_markov_junior_markov_junior_session_destructor(session);
    return false;
  }
  ret->handle = exports_gams_markov_junior_markov_junior_session_new(session);
  if (ret->handle.__handle == 0) {
    exports_gams_markov_junior_markov_junior_grid_free(&ret->grid);
    exports_gams_markov_junior_markov_junior_session_destructor(session);
    markov_junior_plugin_string_dup(err, "failed to create session resource");
    return false;
  }
  return true;
}

bool exports_gams_markov_junior_markov_junior_step(
    exports_gams_markov_junior_markov_junior_borrow_session_t handle,
    uint32_t steps,
    exports_gams_markov_junior_markov_junior_grid_t *ret,
    markov_junior_plugin_string_t *err) {
  if (!handle || handle->dismissed) {
    markov_junior_plugin_string_dup(err, "markov session is dismissed");
    return false;
  }
  uint32_t status = mj_core_session_step(handle->core_session, steps);
  if (status != 0) {
    set_error(err);
    return false;
  }
  return parse_grid_result(ret, err);
}

bool exports_gams_markov_junior_markov_junior_dismiss(
    exports_gams_markov_junior_markov_junior_borrow_session_t handle,
    markov_junior_plugin_string_t *err) {
  (void)err;
  if (!handle) return true;
  if (!handle->dismissed && handle->core_session) {
    mj_core_session_destroy(handle->core_session);
    handle->core_session = NULL;
  }
  handle->dismissed = true;
  return true;
}

void exports_gams_markov_junior_markov_junior_session_destructor(
    exports_gams_markov_junior_markov_junior_session_t *rep) {
  if (!rep) return;
  if (rep->core_session) mj_core_session_destroy(rep->core_session);
  free(rep);
}

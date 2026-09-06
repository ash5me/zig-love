return [[
typedef struct EngineContext EngineContext;

typedef struct {
    uint32_t buttons;
    float mouse_x;
    float mouse_y;
} InputState;
typedef struct {
    uint32_t id;
    uint32_t value;
} EngineEvent;

EngineContext* engine_create(size_t capacity, size_t grid_width, size_t grid_height, float cell_size);
void engine_destroy(EngineContext* context);
size_t engine_entity_capacity(const EngineContext* context);
size_t engine_alive_count(const EngineContext* context);
float* engine_positions_x(EngineContext* context);
float* engine_positions_y(EngineContext* context);
uint64_t* engine_sprite_ids(EngineContext* context);
uint32_t engine_spawn(EngineContext* context, uint64_t id, float x, float y, float velocity_x, float velocity_y, uint64_t sprite_id);
bool engine_destroy_entity(EngineContext* context, uint32_t index);
uint32_t engine_find_entity(const EngineContext* context, uint64_t id);
void engine_rebuild_spatial(EngineContext* context);
size_t engine_query_cell(const EngineContext* context, int32_t cell_x, int32_t cell_y, uint32_t* output, size_t output_capacity);
void engine_set_input(EngineContext* context, const InputState* input);
bool engine_next_event(EngineContext* context, EngineEvent* output);
size_t engine_pending_event_count(const EngineContext* context);
bool engine_pathfind_begin(EngineContext* context, int32_t start_x, int32_t start_y, int32_t goal_x, int32_t goal_y);
uint32_t engine_pathfind_step(EngineContext* context, size_t node_budget);
uint32_t engine_pathfind_state(const EngineContext* context);
size_t engine_pathfind_length(const EngineContext* context);
void engine_update(EngineContext* context, float dt);
int add_numbers(int a, int b);
]]

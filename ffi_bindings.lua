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
typedef struct {
    uint64_t physics_us;
    uint64_t spatial_sort_us;
    uint64_t ffi_serialization_us;
    uint64_t frame_us;
} Telemetry;
typedef struct {
    uint32_t entity_index;
    uint64_t entity_id;
    float x;
    float y;
    float distance;
} RaycastHit;
typedef struct {
    float x;
    float y;
    float scale;
    float rotation;
    float parallax_x;
    float parallax_y;
    float viewport_width;
    float viewport_height;
} CameraState;

EngineContext* engine_create(size_t capacity, size_t grid_width, size_t grid_height, float cell_size);
void engine_destroy(EngineContext* context);
size_t engine_entity_capacity(const EngineContext* context);
size_t engine_alive_count(const EngineContext* context);
Telemetry* engine_telemetry(EngineContext* context);
void engine_set_gravity(EngineContext* context, float gravity);
float engine_get_gravity(const EngineContext* context);
float* engine_positions_x(EngineContext* context);
float* engine_positions_y(EngineContext* context);
float* engine_velocities_x(EngineContext* context);
float* engine_velocities_y(EngineContext* context);
uint64_t* engine_sprite_ids(EngineContext* context);
bool engine_set_position(EngineContext* context, uint32_t index, float x, float y);
bool engine_set_velocity(EngineContext* context, uint32_t index, float x, float y);
uint32_t engine_spawn(EngineContext* context, uint64_t id, float x, float y, float velocity_x, float velocity_y, uint64_t sprite_id);
bool engine_destroy_entity(EngineContext* context, uint32_t index);
bool engine_anchor_entity(EngineContext* context, uint32_t index);
bool engine_release_entity(EngineContext* context, uint32_t index);
uint32_t engine_entity_anchor_count(const EngineContext* context, uint32_t index);
void engine_camera_set(EngineContext* context, const CameraState* camera);
const float* engine_camera_matrix(const EngineContext* context);
bool engine_set_render_z(EngineContext* context, uint32_t index, int32_t z);
void engine_sort_render_order(EngineContext* context);
const uint32_t* engine_render_order(EngineContext* context);
size_t engine_render_count(const EngineContext* context);
bool engine_animation_set(EngineContext* context, uint32_t index, uint64_t first_frame_id, uint32_t frame_count, float frame_duration, bool loop);
uint64_t engine_current_sprite_frame_id(const EngineContext* context, uint32_t index);
bool engine_set_body(EngineContext* context, uint32_t index, uint8_t body_type, uint8_t shape_type, float radius, float half_length);
bool engine_test_collision(const EngineContext* context, uint32_t first, uint32_t second);
bool engine_raycast(const EngineContext* context, float ax, float ay, float bx, float by, RaycastHit* output);
uint32_t engine_find_entity(const EngineContext* context, uint64_t id);
void engine_rebuild_spatial(EngineContext* context);
size_t engine_query_cell(const EngineContext* context, int32_t cell_x, int32_t cell_y, uint32_t* output, size_t output_capacity);
void engine_set_input(EngineContext* context, const InputState* input);
bool engine_next_event(EngineContext* context, EngineEvent* output);
size_t engine_pending_event_count(const EngineContext* context);
void engine_frame_begin(EngineContext* context);
uint8_t* engine_frame_alloc(EngineContext* context, size_t size);
size_t engine_frame_arena_used(const EngineContext* context);
size_t engine_frame_arena_capacity(const EngineContext* context);
size_t engine_snapshot_size(const EngineContext* context);
size_t engine_snapshot_write(EngineContext* context, uint8_t* output, size_t output_capacity);
bool engine_snapshot_read(EngineContext* context, const uint8_t* input, size_t input_size);
bool engine_pathfind_begin(EngineContext* context, int32_t start_x, int32_t start_y, int32_t goal_x, int32_t goal_y);
uint32_t engine_pathfind_step(EngineContext* context, size_t node_budget);
uint32_t engine_pathfind_state(const EngineContext* context);
size_t engine_pathfind_length(const EngineContext* context);
void engine_update(EngineContext* context, float dt);
int add_numbers(int a, int b);
]]

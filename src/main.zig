const std = @import("std");
const nri = @import("nri");
const zglfw = @import("zglfw");
const zmath = @import("zmath");

const Descs = nri.Descs;

const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 600;
const QUEUED_FRAME_NUM = 4;
const TITLE_BASE = "NRI Spinning Cube";

const CubeShader = @import("shaders/cube.zig");

// Cube vertex data (position + color interleaved)
const CubeVertex = extern struct {
    pos: [3]f32,
    color: [3]f32,
};

const cube_vertices = [_]CubeVertex{
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .color = .{ 0.0, 0.0, 0.0 } }, // 0
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .color = .{ 1.0, 0.0, 0.0 } }, // 1
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .color = .{ 1.0, 1.0, 0.0 } }, // 2
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .color = .{ 0.0, 1.0, 0.0 } }, // 3
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .color = .{ 0.0, 0.0, 1.0 } }, // 4
    .{ .pos = .{ 0.5, -0.5, 0.5 }, .color = .{ 1.0, 0.0, 1.0 } }, // 5
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .color = .{ 1.0, 1.0, 1.0 } }, // 6
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .color = .{ 0.0, 1.0, 1.0 } }, // 7
};

const cube_indices = [_]u16{
    0, 1, 2, 0, 2, 3, // front
    1, 5, 6, 1, 6, 2, // right
    5, 4, 7, 5, 7, 6, // back
    4, 0, 3, 4, 3, 7, // left
    3, 2, 6, 3, 6, 7, // top
    4, 5, 1, 4, 1, 0, // bottom
};

pub fn main(init: std.process.Init) !void {
    // initialize GLFW
    zglfw.init() catch return;
    defer zglfw.terminate();
    zglfw.windowHint(.client_api, .no_api);
    zglfw.windowHint(.resizable, false);

    const window = zglfw.createWindow(WINDOW_WIDTH, WINDOW_HEIGHT, TITLE_BASE, null, null) catch return;
    defer window.destroy();

    const device = try nri.DeviceCreation.createDevice(.{
        .graphics_api = .VK,
        .enable_graphics_api_validation = true,
        .enable_nri_validation = true,
    });
    defer nri.DeviceCreation.destroyDevice(device);

    const Core = try nri.getInterface(nri.CoreInterface, device);
    const SwapChain = try nri.getInterface(nri.SwapChain.SwapChainInterface, device);

    const gfx_queue = try Core.getQueue(device, .GRAPHICS, 0);

    var nri_window: nri.SwapChain.Window = .{};
    if (zglfw.getX11Display()) |x11_display| {
        nri_window.x11 = .{
            .dpy = x11_display,
            .window = @intCast(zglfw.getX11Window(window)),
        };
    } else if (zglfw.getWaylandDisplay()) |wl_display| {
        nri_window.wayland = .{
            .display = wl_display,
            .surface = zglfw.getWaylandWindow(window),
        };
    } else {
        std.debug.print("No supported windowing system\n", .{});
        return;
    }

    const swap_chain = try SwapChain.create(device, .{
        .window = nri_window,
        .queue = gfx_queue,
        .width = WINDOW_WIDTH,
        .height = WINDOW_HEIGHT,
        .texture_num = QUEUED_FRAME_NUM + 1,
        .format = .BT709_G22_8BIT,
        .flags = .{
            .vsync = false,
            .allow_low_latency = true,
            .allow_tearing = true,
            .waitable = false,
        },
    });
    defer SwapChain.destroy(swap_chain);

    const swap_textures = SwapChain.getTextures(swap_chain);
    const swap_format = Core.GetTextureDesc(swap_textures[0]).format;

    // create texture views for rendering
    var swap_views: [8]*Descs.Descriptor = undefined;
    for (swap_textures, 0..) |texture, i| {
        swap_views[i] = try Core.createTextureView(.{
            .texture = texture,
            .type = .COLOR_ATTACHMENT,
            .format = swap_format,
        });
    }
    defer for (0..swap_textures.len) |i| Core.DestroyDescriptor(swap_views[i]);

    // track which swapchain images have been initialized
    var texture_initialized = [_]bool{false} ** 8;

    // create pipeline layout with push constants for angle & view_projection
    const pipeline_layout = try Core.createPipelineLayout(device, .{
        .root_register_space = 0,
        .root_constants = &.{
            .constant(CubeShader.PushConstants, 0, .{ .vertex_shader = true }),
        },
        .shader_stages = .{ .vertex_shader = true, .fragment_shader = true },
    });
    defer Core.DestroyPipelineLayout(pipeline_layout);

    const pipeline = try Core.createGraphicsPipeline(device, .{
        .pipeline_layout = pipeline_layout,
        .vertex_input = .{
            .attributes = &.{
                .{
                    .d3d = .{ .semantic_name = "POSITION", .semantic_index = 0 },
                    .vk = .{ .location = 0 },
                    .offset = 0,
                    .format = .RGB32_SFLOAT,
                    .stream_index = 0,
                },
                .{
                    .d3d = .{ .semantic_name = "COLOR", .semantic_index = 0 },
                    .vk = .{ .location = 1 },
                    .offset = @sizeOf(f32) * 3,
                    .format = .RGB32_SFLOAT,
                    .stream_index = 0,
                },
            },
            .streams = &.{
                .{
                    .binding_slot = 0,
                    .step_rate = .PER_VERTEX,
                },
            },
        },
        .input_assembly = .{
            .topology = .TRIANGLE_LIST,
            .tess_control_point_num = 0,
            .primitive_restart = .DISABLED,
        },
        .rasterization = .{
            .fill_mode = .SOLID,
            .cull_mode = .BACK,
        },
        .output_merger = .{
            .colors = &.{
                .{
                    .format = swap_format,
                    .color_blend = .{
                        .src_factor = .ONE,
                        .dst_factor = .ZERO,
                        .op = .ADD,
                    },
                    .alpha_blend = .{
                        .src_factor = .ONE,
                        .dst_factor = .ZERO,
                        .op = .ADD,
                    },
                    .color_write_mask = .RGBA,
                    .blend_enabled = false,
                },
            },
        },
        .shaders = &.{
            CubeShader.Fragment,
            CubeShader.Vertex,
        },
    });
    defer Core.DestroyPipeline(pipeline);

    // create vertex buffer
    const vb = try Core.createCommittedBuffer(device, .HOST_UPLOAD, 0.5, .{
        .size = @sizeOf(@TypeOf(cube_vertices)),
        .structure_stride = @sizeOf(CubeVertex),
        .usage = .{ .vertex_buffer = true },
    });
    defer Core.DestroyBuffer(vb);

    @memcpy(
        Core.mapBuffer(vb, @sizeOf(@TypeOf(cube_vertices))),
        @as([*]const u8, @ptrCast(&cube_vertices)),
    );
    Core.UnmapBuffer(vb);

    // create index buffer
    const ib = try Core.createCommittedBuffer(device, .HOST_UPLOAD, 0.5, .{
        .size = @sizeOf(@TypeOf(cube_indices)),
        .usage = .{ .index_buffer = true },
    });
    defer Core.DestroyBuffer(ib);

    @memcpy(
        Core.mapBuffer(ib, @sizeOf(@TypeOf(cube_indices))),
        @as([*]const u8, @ptrCast(&cube_indices)),
    );
    Core.UnmapBuffer(ib);

    // create one command allocator and command buffer per frame slot
    var cmd_allocators = try Core.createManyCommandAllocators(QUEUED_FRAME_NUM, gfx_queue);
    defer for (&cmd_allocators) |a| Core.DestroyCommandAllocator(a);
    var cmd_buffers = try Core.createManyCommandBuffers(QUEUED_FRAME_NUM, cmd_allocators);
    defer for (&cmd_buffers) |cb| Core.DestroyCommandBuffer(cb);

    // fence for CPU/GPU frame synchronization
    const frame_fence = try Core.createFence(device, 0);
    defer Core.DestroyFence(frame_fence);

    // swapchain semaphores (one per swapchain image)
    var acquire_semaphores = try Core.createManyFences(8, device, swap_textures.len, nri.SwapChain.SWAPCHAIN_SEMAPHORE);
    defer for (acquire_semaphores[0..swap_textures.len]) |f| Core.DestroyFence(f);
    var release_semaphores = try Core.createManyFences(8, device, swap_textures.len, nri.SwapChain.SWAPCHAIN_SEMAPHORE);
    defer for (release_semaphores[0..swap_textures.len]) |f| Core.DestroyFence(f);

    var frame_index: u64 = 0;

    // render loop
    while (!window.shouldClose()) {
        zglfw.pollEvents();

        const now = std.Io.Timestamp.now(init.io, .cpu_process);
        const angle: f32 = @floatCast(@as(f64, @floatFromInt(now.toNanoseconds())) / std.time.ns_per_s * 1.5);

        const aspect = @as(f32, @floatFromInt(WINDOW_WIDTH)) / @as(f32, @floatFromInt(WINDOW_HEIGHT));
        const projection = zmath.perspectiveFovRh(std.math.pi / 4.0, aspect, 0.1, 100.0);
        const view = zmath.lookAtRh(.{ 0.0, 0.0, 3.0, 1.0 }, .{ 0.0, 0.0, 0.0, 0.0 }, .{ 0.0, 1.0, 0.0, 0.0 });
        const view_projection = zmath.mul(view, projection);

        const push_constants: CubeShader.PushConstants = .{
            .angle = angle,
            .view_projection = view_projection,
        };

        // wait for in-flight frame (CPU waits for GPU)
        if (frame_index >= QUEUED_FRAME_NUM)
            Core.Wait(frame_fence, 1 + frame_index - QUEUED_FRAME_NUM);

        const slot: usize = frame_index % QUEUED_FRAME_NUM;
        Core.ResetCommandAllocator(cmd_allocators[slot]);

        // Select semaphore slot and acquire next swapchain texture
        const sem_slot: usize = frame_index % swap_textures.len;
        const acquire_sem = acquire_semaphores[sem_slot];
        const ti: u32 = try SwapChain.acquireNextTexture(swap_chain, acquire_sem);
        const release_sem = release_semaphores[ti];

        const cmd = cmd_buffers[slot];
        const tex = swap_textures[ti];

        // record commands
        try Core.beginCommandBuffer(cmd, null);

        // start-of-frame barrier: determine initial layout state for this swapchain image
        Core.cmdBarrier(cmd, .{
            .texture = &.{
                .{
                    .texture = tex,
                    .before = .{
                        .access = .{},
                        .layout = if (texture_initialized[ti]) .PRESENT else .UNDEFINED,
                        .stages = if (texture_initialized[ti]) .NONE else .ALL,
                    },
                    .after = .{
                        .access = .COLOR_ATTACHMENT,
                        .layout = .COLOR_ATTACHMENT,
                        .stages = .{ .color_attachment = true },
                    },
                },
            },
        });

        Core.cmdSetViewports(cmd, &.{
            .{
                .x = 0,
                .y = 0,
                .width = WINDOW_WIDTH,
                .height = WINDOW_HEIGHT,
                .depth_min = 0.0,
                .depth_max = 1.0,
                .origin_bottom_left = false,
            },
        });
        Core.cmdSetScissors(cmd, &.{
            .{ .x = 0, .y = 0, .width = WINDOW_WIDTH, .height = WINDOW_HEIGHT },
        });

        // begin rendering
        Core.cmdBeginRendering(cmd, .{
            .colors = &.{
                .{
                    .descriptor = swap_views[ti],
                    .clear_value = .{
                        .color = .{ .f = .{ .x = 0.1, .y = 0.1, .z = 0.1, .w = 1.0 } },
                    },
                    .load_op = .CLEAR,
                    .store_op = .STORE,
                    .resolve_op = .AVERAGE,
                    .resolve_dst = null,
                },
            },
        });
        {
            // Draw cube
            Core.cmdSetPipelineLayout(cmd, .GRAPHICS, pipeline_layout);
            Core.cmdSetPipeline(cmd, pipeline);
            Core.cmdSetRootConstants(cmd, .{
                .root_constant_index = 0,
                .data = @ptrCast(&push_constants),
                .size = @sizeOf(CubeShader.PushConstants),
            });
            Core.cmdSetVertexBuffers(cmd, 0, &.{
                .{
                    .buffer = vb,
                    .offset = 0,
                    .stride = @sizeOf(CubeVertex),
                },
            });
            Core.cmdSetIndexBuffer(cmd, ib, 0, .UINT16);
            Core.cmdDrawIndexed(cmd, .{
                .index_num = cube_indices.len,
                .instance_num = 1,
                .base_index = 0,
                .base_vertex = 0,
                .base_instance = 0,
            });
        }
        Core.cmdEndRendering(cmd);

        // end-of-frame barrier: transition to PRESENT
        Core.cmdBarrier(cmd, .{
            .texture = &.{
                .{
                    .texture = tex,
                    .before = .{
                        .access = .COLOR_ATTACHMENT,
                        .layout = .COLOR_ATTACHMENT,
                        .stages = .{ .color_attachment = true },
                    },
                    .after = .{
                        .access = .NONE,
                        .layout = .PRESENT,
                        .stages = .NONE,
                    },
                },
            },
        });

        texture_initialized[ti] = true;

        try Core.endCommandBuffer(cmd);

        // submit command buffer, with wait/signal semaphores
        try Core.queueSubmit(gfx_queue, .{
            .wait_fences = &.{
                .{
                    .fence = acquire_sem,
                    .value = 0,
                    .stages = .{ .color_attachment = true },
                },
            },
            .command_buffers = &.{cmd},
            .signal_fences = &.{
                .{ .fence = release_sem, .value = 0, .stages = .ALL },
                .{ .fence = frame_fence, .value = 1 + frame_index, .stages = .ALL },
            },
            .swap_chain = swap_chain,
        });

        // present the swapchain image
        try SwapChain.queuePresent(swap_chain, release_sem);

        frame_index += 1;
    }

    try Core.DeviceWaitIdle(device).success();
}

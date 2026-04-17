pub const PushConstants = extern struct {
    angle: f32,
    view_projection: zmath.Mat,
};

const Vec2f = @Vector(2, f32);
const Vec3f = @Vector(3, f32);
const Vec4f = @Vector(4, f32);

extern const pc: PushConstants addrspace(.push_constant);
const in_pos = @extern(*addrspace(.input) Vec3f, .{ .name = "in_pos", .decoration = .{ .location = 0 } });
const in_color = @extern(*addrspace(.input) Vec3f, .{ .name = "in_color", .decoration = .{ .location = 1 } });
const out_frag_color = @extern(*addrspace(.output) Vec3f, .{ .name = "out_frag_color", .decoration = .{ .location = 0 } });

fn vertexMain() callconv(.spirv_vertex) void {
    const angle = pc.angle;

    // rotate around X axis
    const cx = std.math.cos(angle * 0.7);
    const sx = std.math.sin(angle * 0.7);
    const pos1: Vec3f = .{ in_pos[0], in_pos[1] * cx - in_pos[2] * sx, in_pos[1] * sx + in_pos[2] * cx };

    // rotate around Y axis
    const cy = std.math.cos(angle * 0.5);
    const sy = std.math.sin(angle * 0.5);
    const pos2: Vec3f = .{ pos1[0] * cy + pos1[2] * sy, pos1[1], -pos1[0] * sy + pos1[2] * cy };

    // rotate around Z axis
    const cz = std.math.cos(angle * 0.3);
    const sz = std.math.sin(angle * 0.3);
    const rotated: Vec3f = .{ pos2[0] * cz - pos2[1] * sz, pos2[0] * sz + pos2[1] * cz, pos2[2] };

    // apply view-projection matrix
    const world_pos: Vec4f = .{ rotated[0] * 0.7, rotated[1] * 0.7, rotated[2] * 0.7, 1.0 };
    gpu.position_out.* = zmath.mul(world_pos, pc.view_projection);
    out_frag_color.* = in_color.*;
}

const frag_color = @extern(*addrspace(.input) Vec3f, .{ .name = "frag_color", .decoration = .{ .location = 0 } });
const out_color = @extern(*addrspace(.output) Vec4f, .{ .name = "out_color", .decoration = .{ .location = 0 } });

fn fragmentMain() callconv(.spirv_fragment) void {
    out_color.* = .{ frag_color[0], frag_color[1], frag_color[2], 1.0 };
}

comptime {
    if (builtin.cpu.arch.isSpirV()) {
        @export(&vertexMain, .{ .name = "vertexMain" });
        @export(&fragmentMain, .{ .name = "fragmentMain" });
    }
}

const bytecode = @embedFile("cube.spv");

pub const Fragment: nri.Descs.ShaderDesc = .from(.{
    .stage = .{ .fragment_shader = true },
    .bytecode = bytecode,
    .entry_point_name = "fragmentMain",
});

pub const Vertex: nri.Descs.ShaderDesc = .from(.{
    .stage = .{ .vertex_shader = true },
    .bytecode = bytecode,
    .entry_point_name = "vertexMain",
});

const nri = @import("nri");
const std = @import("std");
const builtin = @import("builtin");
const zmath = @import("zmath");

const gpu = std.gpu;

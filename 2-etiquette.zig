const std = @import("std");

const Header = struct {
    len: usize,
    free: bool,
};

const header_alignment = std.mem.Alignment.of(Header);

const AllocateurEtiquette = struct {
    buffer: []u8,
    next: usize,

    /// Crée un allocateur à étiquetage gérant la zone de mémoire délimitée
    /// par la tranche `buffer`.
    fn init(buffer: []u8) AllocateurEtiquette {
        return .{
            .buffer = buffer,
            .next = 0,
        };
    }

    /// Retourne l’interface générique d’allocateur correspondant à
    /// cet allocateur à étiquetage.
    fn allocator(self: *AllocateurEtiquette) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .free = free,
                .resize = std.mem.Allocator.noResize,
                .remap = std.mem.Allocator.noRemap,
            },
        };
    }

    /// Tente d’allouer un bloc de mémoire de `len` octets dont l’adresse
    /// est alignée suivant `alignment`. Retourne un pointeur vers le début
    /// du bloc alloué, ou `null` pour indiquer un échec d’allocation.
    fn alloc(
        ctx: *anyopaque,
        len: usize,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) ?[*]u8 {
        // le paramètre `return_address` peut être ignoré dans ce contexte
        _ = return_address;

        // récupère un pointeur vers l’instance de notre allocateur
        const self: *AllocateurEtiquette = @ptrCast(@alignCast(ctx));

        const base_addr = @intFromPtr(&self.buffer[0]);
        const size_of_header = @sizeOf(Header);

        const curr_addr = base_addr + self.next;
        const aligned_addr = std.mem.alignForward(
            usize, 
            curr_addr + size_of_header, 
            @max(
                alignment.toByteUnits(),
                @alignOf(Header)
                )
            );

        const offset = aligned_addr - base_addr;
        const new_next = offset + len;

        if (new_next > self.buffer.len) {
            return null;
        }
        
        const header_address = aligned_addr - size_of_header; 
        const header_ptr: *Header = @ptrFromInt(header_address);
        header_ptr.*= .{
            .len = len,
            .free = false,
        };
        
        self.next = new_next;

        return @ptrFromInt(aligned_addr);
    }

    /// Récupère l’en-tête associé à l’allocation débutant à l’adresse `ptr`.
    fn getHeader(ptr: [*]u8) *Header {
        const ptr_address = @intFromPtr(ptr);
        const header_address = ptr_address - @sizeOf(Header);
        return @ptrFromInt(header_address); 
    }

    /// Marque un bloc de mémoire précédemment alloué comme étant libre.
    fn free(
        ctx: *anyopaque,
        buf: []u8,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) void {
        // les paramètres `ctx`, `alignment` et `return_address`
        // peuvent être ignorés dans ce contexte
        _ = ctx;
        _ = alignment;
        _ = return_address;

        const buffer_ptr = buf.ptr; 
        const mem_add_to_free = @intFromPtr(buffer_ptr);
        const header_address = mem_add_to_free - @sizeOf(Header);
        const header_ptr : *Header = @ptrFromInt(header_address);
        header_ptr.*.free = true;
    }
};

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "allocations simples" {
    var buffer: [128]u8 = undefined;
    var etiquette = AllocateurEtiquette.init(&buffer);
    const allocator = etiquette.allocator();

    const a = try allocator.create(u8);
    const b = try allocator.create(u8);
    const c = try allocator.create(u8);
    const d = try allocator.create(u8);

    try expect(@intFromPtr(a) + 1 <= @intFromPtr(b));
    try expect(@intFromPtr(b) + 1 <= @intFromPtr(c));
    try expect(@intFromPtr(c) + 1 <= @intFromPtr(d));

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(a)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(a)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(b)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(b)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(c)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(c)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(d)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(d)).len);

    a.* = 4;
    b.* = 5;
    c.* = 6;
    d.* = 7;

    try expectEqual(4, a.*);
    try expectEqual(5, b.*);
    try expectEqual(6, c.*);
    try expectEqual(7, d.*);

    allocator.destroy(c);

    try expectEqual(true, AllocateurEtiquette.getHeader(@ptrCast(c)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(c)).len);
}

test "allocations à plusieurs octets" {
    var buffer: [128]u8 = undefined;
    var etiquette = AllocateurEtiquette.init(&buffer);
    const allocator = etiquette.allocator();

    const a = try allocator.create(u8);
    const b = try allocator.create(u64);
    const c = try allocator.create(u8);
    const d = try allocator.create(u16);

    try expect(@intFromPtr(a) + 1 <= @intFromPtr(b));
    try expect(@intFromPtr(b) + 8 <= @intFromPtr(c));
    try expect(@intFromPtr(c) + 1 <= @intFromPtr(d));

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(a)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(a)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(b)).free);
    try expectEqual(8, AllocateurEtiquette.getHeader(@ptrCast(b)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(c)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(c)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(d)).free);
    try expectEqual(2, AllocateurEtiquette.getHeader(@ptrCast(d)).len);

    a.* = 4;
    b.* = 5;
    c.* = 6;
    d.* = 7;

    try expectEqual(4, a.*);
    try expectEqual(5, b.*);
    try expectEqual(6, c.*);
    try expectEqual(7, d.*);

    allocator.destroy(b);

    try expectEqual(true, AllocateurEtiquette.getHeader(@ptrCast(b)).free);
    try expectEqual(8, AllocateurEtiquette.getHeader(@ptrCast(b)).len);
}

test "allocation de tableaux" {
    var buffer: [128]u8 = undefined;
    var etiquette = AllocateurEtiquette.init(&buffer);
    const allocator = etiquette.allocator();

    const a = try allocator.alloc(u8, 1);
    const b = try allocator.alloc(u32, 10);
    const c = try allocator.create(u64);

    try expect(@intFromPtr(&a[0]) + 1 <= @intFromPtr(&b[0]));
    try expectEqual(10, b.len);
    try expect(@intFromPtr(&b[9]) + 4 <= @intFromPtr(c));

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(a)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(a)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(b)).free);
    try expectEqual(40, AllocateurEtiquette.getHeader(@ptrCast(b)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(c)).free);
    try expectEqual(8, AllocateurEtiquette.getHeader(@ptrCast(c)).len);

    allocator.free(b);

    try expectEqual(true, AllocateurEtiquette.getHeader(@ptrCast(b)).free);
    try expectEqual(40, AllocateurEtiquette.getHeader(@ptrCast(b)).len);
}

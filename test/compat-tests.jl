@testitem "compat-tests" begin

module TestBlobsCompat

using Blobs
using Test

# basic sanity checks

struct Foo
    x::Int64
    y::Float32 # tests conversion and alignment
end

foo = Blobs.malloc_and_init(Foo)
@v foo.x = 1
@test @v(foo.x) == 1
@v foo.y = 2.5
@test (@v foo.y) == 2.5
@test (@v foo) == Foo(1,2.5)
# tests interior pointers
@test (@a foo) == foo
@test pointer(@a foo.y) == pointer(foo) + sizeof(Int64)

# tests ambiguous syntax
@test_throws LoadError eval(:(@v foo.y == 2.5))
@test_throws LoadError eval(:(@a foo.y == 2.5))

mpv = Blobs.malloc_and_init(BlobVector{Foo}, 3)
pv = @v mpv
pv[2] = Foo(2, 2.2)
@test pv[2] == Foo(2, 2.2)
@test length(pv) == 3
pv[1] = Foo(1, 1.1)
pv[3] = Foo(3, 3.3)
# tests iteration
@test collect(pv) == [Foo(1,1.1), Foo(2,2.2), Foo(3,3.3)]
# tests interior pointers
@test pointer(@a mpv[2]) - pointer(pv.data) == Blobs.self_size(Foo)

bbv = Blobs.malloc_and_init(BlobBitVector, 3)
pbv = @v bbv
pbv[2] = true
@test pbv[2] == true
@test pv[2] == Foo(2, 2.2)
pbv[1] = false
pbv[3] = false
# tests iteration
@test collect(pbv) == [false, true, false]
fill!(pbv, false)
@test collect(pbv) == [false, false, false]

# strings and unicode

s = "普通话/普通話"
mp = Blobs.malloc_and_init(BlobString, s)
p = @v mp
@test p == s
@test repr(p) == repr(s)
@test collect(p) == collect(s)
@test findfirst(p, "通") == findfirst(s, "通")

# test right-to-left

s = "سلام"
mp = Blobs.malloc_and_init(BlobString, s)
p = @v mp
@test p == s
@test repr(p) == repr(s)
@test collect(p) == collect(s)
@test findfirst(p, "ا") == findfirst(s, "ا")

# test string conversions

@test isbits(p)
@test String(p) isa String
@test String(p) == s

# test string slices

s = "aye bee sea"
mp = Blobs.malloc_and_init(BlobString, s)
p = @v mp
@test p[5:7] isa BlobString
@test p[5:7] == "bee"

# sketch of paged pmas

struct PackedMemoryArray{K,V}
     keys::BlobVector{K}
     values::BlobVector{V}
     mask::BlobBitVector
     count::Int
     #...other stuff
end

function Blobs.child_size(::Type{PackedMemoryArray{K,V}}, length::Int64) where {K,V}
    T = PackedMemoryArray{K,V}
    +(Blobs.child_size(fieldtype(T, :keys), length),
      Blobs.child_size(fieldtype(T, :values), length),
      Blobs.child_size(fieldtype(T, :mask), length))
  end

function Blobs.init(pma::Blob{PackedMemoryArray{K,V}}, free::Blob{Nothing}, length::Int64) where {K,V}
    free = Blobs.init(pma.keys, free, length)
    free = Blobs.init(pma.values, free, length)
    free = Blobs.init(pma.mask, free, length)
    fill!(pma.mask[], false)
    pma.count[] = 0
    free
end

pma = Blobs.malloc_and_init(PackedMemoryArray{Int64, Float32}, 3)
@test (@v pma.count) == 0
@test (@v pma.keys.length) == 3
# tests fill!
@test !any(@v pma.mask)
# tests pointer <-> offset conversion
@test unsafe_load(convert(Ptr{UInt64}, pointer(pma)), 1) == Blobs.self_size(PackedMemoryArray{Int64, Float32})
# tests nested interior pointers
pma2 = pma.mask[2]
@test pma2[] == false
pma2[] = true
@test pma2[] == true
@test pma.mask[2][] == true

# test api works ok with varying sizes

struct Quux
    x::BlobVector{Int}
    y::Float64
end

struct Bar
    a::Int
    b::BlobBitVector
    c::Bool
    d::BlobVector{Float64}
    e::Blob{Quux}
end

function Blobs.child_size(::Type{Quux}, x_len::Int64, y::Float64)
    T = Quux
    +(Blobs.child_size(fieldtype(T, :x), x_len))
end

function Blobs.child_size(::Type{Bar}, b_len::Int64, c::Bool, d_len::Int64, x_len::Int64, y::Float64)
    T = Bar
    +(Blobs.child_size(fieldtype(T, :b), b_len),
      Blobs.child_size(fieldtype(T, :d), d_len),
      Blobs.child_size(fieldtype(T, :e), x_len, y))
end

function Blobs.init(quux::Blob{Quux}, free::Blob{Nothing}, x_len::Int64, y::Float64)
    free = Blobs.init(quux.x, free, x_len)
    quux.y[] = y
    free
end

function Blobs.init(bar::Blob{Bar}, free::Blob{Nothing}, b_len::Int64, c::Bool, d_len::Int64, x_len::Int64, y::Float64)
    free = Blobs.init(bar.b, free, b_len)
    free = Blobs.init(bar.d, free, d_len)
    free = Blobs.init(bar.e, free, x_len, y)
    bar.c[] = c
    free
end

bar = Blobs.malloc_and_init(Bar, 10, false, 20, 15, 1.5)
quux = @v bar.e

@test length(@v bar.b) == 10
@test (@v bar.c) == false
@test length(@v bar.d) == 20
@test length(@v quux.x) == 15
@test (@v quux.y) == 1.5

end

end  # testitem

module TestBlobs

using Blobs
import Blobs
using Base.Test

struct Foo
    x::Int64
    y::Float32 # tests conversion and alignment
end

# Blob

foo = Blobs.malloc_and_init(Blob{Foo}) # display should work in 0.7 TODO fix for 0.6?
@v foo.x = 1
@test @v(foo.x) == 1
@v foo.y = 2.5
@test (@v foo.y) == 2.5
@test (@v foo) == Foo(1,2.5)
# test interior pointers
@test (@a foo) == foo
@test (@a foo.y).ptr == foo.ptr + sizeof(Int64)

# test ambiguous syntax
@test_throws ErrorException eval(:(@v foo.y == 2.5))
@test_throws ErrorException eval(:(@a foo.y == 2.5))

# BlobVector

bbv = Blobs.malloc_and_init(BlobVector{Foo}, 3)
bv = @v bbv
bv[2] = Foo(2, 2.2)
@test bv[2] == Foo(2, 2.2)
@test (@v bv[2]) == Foo(2, 2.2)
@test length(bv) == 3
bv[1] = Foo(1, 1.1)
bv[3] = Foo(3, 3.3)
# test iteration
@test collect(bv) == [Foo(1,1.1), Foo(2,2.2), Foo(3,3.3)]
# test interior pointers
@test (@a bv[2]).ptr == bv.data.ptr + sizeof(Foo)

# BlobBitVector

bbv = Blobs.malloc_and_init(BlobBitVector, 3)
bv = @v bbv
bv[2] = true
@test bv[2] == true
@test (@v bv[2]) == true
@test length(bv) == 3
bv[1] = false
bv[3] = false
# test iteration
@test collect(bv) == [false, true, false]
fill!(bv, false)
@test collect(bv) == [false, false, false]
# test interior pointers
bv2 = @a bv[2]
@test (@v bv2) == false
@v bv2 = true
@test (@v bv2) == true
@test bv[2] == true

# BlobString

# test strings and unicode
s = "普通话/普通話"
bbs = Blobs.malloc_and_init(BlobString, s)
bs = @v bbs
@test bs == s
@test repr(bs) == repr(s)
@test collect(bs) == collect(s)
@test search(bs, "通") == search(s, "通")
@test rsearch(bs, "通") == rsearch(s, "通")
@test reverse(bs) == reverse(s)

# test right-to-left
s = "سلام"
bbs = Blobs.malloc_and_init(BlobString, s)
bs = @v bbs
@test bs == s
@test repr(bs) == repr(s)
@test collect(bs) == collect(s)
@test search(bs, "ا") == search(s, "ا")
@test rsearch(bs, "ا") == rsearch(s, "ا")
@test reverse(bs) == reverse(s)

# test string conversions

@test isbits(bs)
@test reverse(bs) isa RevString{BlobString}
@test String(bs) isa String
@test String(bs) == s
@test string(bs) isa String

# sketch of paged pmas

struct PackedMemoryArray{K,V}
     keys::BlobVector{K}
     values::BlobVector{V}
     mask::BlobBitVector
     count::Int
     #...other stuff
end

function Blobs.alloc_size(::Type{PackedMemoryArray{K,V}}, length::Int64) where {K,V}
    T = PackedMemoryArray{K,V}
    +(Blobs.alloc_size(fieldtype(T, :keys), length),
      Blobs.alloc_size(fieldtype(T, :values), length),
      Blobs.alloc_size(fieldtype(T, :mask), length))
  end

function Blobs.init(pma::Blob{PackedMemoryArray{K,V}}, free::Blob{Void}, length::Int64) where {K,V}
    free = Blobs.init((@a pma.keys), free, length)
    free = Blobs.init((@a pma.values), free, length)
    free = Blobs.init((@a pma.mask), free, length)
    fill!((@v pma.mask), false)
    @v pma.count = 0
    free
end

pma = Blobs.malloc_and_init(PackedMemoryArray{Int64, Float32}, 3)
@test (@v pma.count) == 0
@test (@v pma.keys.length) == 3
# tests fill!
@test !any(@v pma.mask)
# tests pointer <-> offset conversion
@test unsafe_load(convert(Ptr{UInt64}, pma.ptr), 1) == sizeof(PackedMemoryArray{Int64, Float32})
# tests nested interior pointers
pma2 = @a pma.mask[2]
@test (@v pma2) == false
@v pma2 = true
@test (@v pma2) == true
@test (@v pma.mask[2]) == true

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

function Blobs.alloc_size(::Type{Quux}, x_len::Int64, y::Float64)
    T = Quux
    +(Blobs.alloc_size(fieldtype(T, :x), x_len))
end

function Blobs.alloc_size(::Type{Bar}, b_len::Int64, c::Bool, d_len::Int64, x_len::Int64, y::Float64)
    T = Bar
    +(Blobs.alloc_size(fieldtype(T, :b), b_len),
      Blobs.alloc_size(fieldtype(T, :d), d_len),
      Blobs.alloc_size(fieldtype(T, :e), x_len, y))
end

function Blobs.init(quux::Blob{Quux}, free::Blob{Void}, x_len::Int64, y::Float64)
    free = Blobs.init((@a quux.x), free, x_len)
    @v quux.y = y
    free
end

function Blobs.init(bar::Blob{Bar}, free::Blob{Void}, b_len::Int64, c::Bool, d_len::Int64, x_len::Int64, y::Float64)
    free = Blobs.init((@a bar.b), free, b_len)
    free = Blobs.init((@a bar.d), free, d_len)
    free = Blobs.init((@a bar.e), free, x_len, y)
    @v bar.c = c
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

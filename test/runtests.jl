module TestBlobs

using Blobs
import Blobs; const MM = Blobs
using Base.Test

# basic sanity checks

struct Foo
    x::Int64
    y::Float32 # tests conversion and alignment
end

foo = Blob{Foo}(Libc.malloc(sizeof(Foo))) # display should work in 0.7 TODO fix for 0.6?
@v foo.x = 1
@test @v(foo.x) == 1
@v foo.y = 2.5
@test (@v foo.y) == 2.5
@test (@v foo) == Foo(1,2.5)
# tests interior pointers
@test (@a foo) == foo
@test (@a foo.y).ptr == foo.ptr + sizeof(Int64)

# tests ambiguous syntax
@test_throws ErrorException eval(:(@v foo.y == 2.5))
@test_throws ErrorException eval(:(@a foo.y == 2.5))

mpv = MM.malloc(BlobVector{Foo}, 3)
pv = @v mpv
pv[2] = Foo(2, 2.2)
@test pv[2] == Foo(2, 2.2)
@test (@v pv[2]) == Foo(2, 2.2)
@test length(pv) == 3
pv[1] = Foo(1, 1.1)
pv[3] = Foo(3, 3.3)
# tests iteration
@test collect(pv) == [Foo(1,1.1), Foo(2,2.2), Foo(3,3.3)]
# tests interior pointers
@test (@a pv[2]).ptr == pv.ptr.ptr + sizeof(Foo)

mpbv = MM.malloc(BlobBitVector, 3)
pbv = @v mpbv
pbv[2] = true
@test pbv[2] == true
@test (@v pv[2]) == Foo(2, 2.2)
pbv[1] = false
pbv[3] = false
# tests iteration
@test collect(pbv) == [false, true, false]
fill!(pbv, false)
@test collect(pbv) == [false, false, false]
# tests interior pointers
pbv2 = @a pbv[2]
@test (@v pbv2) == false
@v pbv2 = true
@test (@v pbv2) == true
@test pbv[2] == true

# strings and unicode

s = "普通话/普通話"
mp = MM.malloc(BlobString, s)
p = @v mp
@test p == s
@test repr(p) == repr(s)
@test collect(p) == collect(s)
@test search(p, "通") == search(s, "通")
@test rsearch(p, "通") == rsearch(s, "通")
@test reverse(p) == reverse(s)

# test right-to-left

s = "سلام"
mp = MM.malloc(BlobString, s)
p = @v mp
@test p == s
@test repr(p) == repr(s)
@test collect(p) == collect(s)
@test search(p, "ا") == search(s, "ا")
@test rsearch(p, "ا") == rsearch(s, "ا")
@test reverse(p) == reverse(s)

# test string conversions

@test isbits(p)
@test reverse(p) isa RevString{BlobString}
@test String(p) isa String
@test String(p) == s
@test string(p) isa String

# sketch of paged pmas

struct PackedMemoryArray{K,V}
     keys::BlobVector{K}
     values::BlobVector{V}
     mask::BlobBitVector
     count::Int
     #...other stuff
end

function MM.alloc_size(::Type{PackedMemoryArray{K,V}}, length::Int64) where {K,V}
    T = PackedMemoryArray{K,V}
    +(MM.alloc_size(fieldtype(T, :keys), length),
      MM.alloc_size(fieldtype(T, :values), length),
      MM.alloc_size(fieldtype(T, :mask), length))
  end

function MM.init(ptr::Ptr{Void}, pma::Blob{PackedMemoryArray{K,V}}, length::Int64) where {K,V}
    ptr = MM.init(ptr, (@a pma.keys), length)
    ptr = MM.init(ptr, (@a pma.values), length)
    ptr = MM.init(ptr, (@a pma.mask), length)
    fill!((@v pma.mask), false)
    @v pma.count = 0
    ptr
end

pma = MM.malloc(PackedMemoryArray{Int64, Float32}, 3)
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

function MM.alloc_size(::Type{Quux}, x_len::Int64, y::Float64)
    T = Quux
    +(MM.alloc_size(fieldtype(T, :x), x_len))
end

function MM.alloc_size(::Type{Bar}, b_len::Int64, c::Bool, d_len::Int64, x_len::Int64, y::Float64)
    T = Bar
    +(MM.alloc_size(fieldtype(T, :b), b_len),
      MM.alloc_size(fieldtype(T, :d), d_len),
      MM.alloc_size(fieldtype(T, :e), x_len, y))
end

function MM.init(ptr::Ptr{Void}, quux::Blob{Quux}, x_len::Int64, y::Float64)
    ptr = MM.init(ptr, (@a quux.x), x_len)
    @v quux.y = y
    ptr
end

function MM.init(ptr::Ptr{Void}, bar::Blob{Bar}, b_len::Int64, c::Bool, d_len::Int64, x_len::Int64, y::Float64)
    ptr = MM.init(ptr, (@a bar.b), b_len)
    ptr = MM.init(ptr, (@a bar.d), d_len)
    ptr = MM.init(ptr, (@a bar.e), x_len, y)
    @v bar.c = c
    ptr
end

bar = MM.malloc(Bar, 10, false, 20, 15, 1.5)
quux = @v bar.e

@test length(@v bar.b) == 10
@test (@v bar.c) == false
@test length(@v bar.d) == 20
@test length(@v quux.x) == 15
@test (@v quux.y) == 1.5

end

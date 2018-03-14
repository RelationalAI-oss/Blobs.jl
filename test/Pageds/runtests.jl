using Base.Test
using Delve.Pageds

# basic sanity checks

struct Foo
    x::Int64
    y::Float32 # tests conversion and alignment
end

foo = Paged{Foo}() # display should work in 0.7 TODO fix for 0.6?
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

pv = PagedVector{Foo}(3)
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

pbv = PagedBitVector(3)
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

# sketch of paged pmas

struct PackedMemoryArray{K,V}
     keys::PagedVector{K}
     values::PagedVector{V}
     mask::PagedBitVector
     count::Int
     #...other stuff
end

function Paged{PackedMemoryArray{K,V}}(length::Int64) where {K,V}
    size = sizeof(PackedMemoryArray{K,V}) + length*sizeof(K) + length*sizeof(V) + Int64(ceil(length/8))
    ptr = Libc.malloc(size)
    pma = Paged{PackedMemoryArray{K,V}}(ptr)
    @v pma.keys = PagedVector{K}(ptr + sizeof(PackedMemoryArray{K,V}), length)
    @v pma.values = PagedVector{V}(ptr + sizeof(PackedMemoryArray{K,V}) + length*sizeof(K), length)
    @v pma.mask = PagedBitVector(ptr + sizeof(PackedMemoryArray{K,V}) + length*sizeof(K) + length*sizeof(V), length)
    fill!((@v pma.mask), false)
    @v pma.count = 0
    pma
end

pma = Paged{PackedMemoryArray{Int64, Float32}}(3)
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

# strings and unicode

s = "普通话/普通話"
p = PagedString(s)
@test isbits(p)
@test p == s
@test repr(p) == repr(s)
@test collect(p) == collect(s)
@test search(p, "通") == search(s, "通")
@test rsearch(p, "通") == rsearch(s, "通")
@test reverse(p) == reverse(s)
@test reverse(p) isa RevString{PagedString}
@test String(p) isa String
@test String(p) == s

# test right-to-left
s = "سلام"
p = PagedString(s)
@test isbits(p)
@test p == s
@test repr(p) == repr(s)
@test collect(p) == collect(s)
@test search(p, "通") == search(s, "通")
@test rsearch(p, "通") == rsearch(s, "通")
@test reverse(p) == reverse(s)
@test reverse(p) isa RevString{PagedString}
@test String(p) isa String
@test String(p) == s

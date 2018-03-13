using Base.Test
using Delve.Pageds

# basic sanity checks

struct Foo
    x::Int64
    y::Float32 # tests conversion and alignment
end

foo = Paged{Foo}() # display should work in 0.7 TODO fix for 0.6?
@paged foo.x[] = 1
@test @paged(foo.x[]) == 1
@paged foo.y[] = 2.5
@test (@paged foo.y[]) == 2.5
@test foo[] == Foo(1,2.5)

# tests ambiguous syntax
@test_throws ErrorException eval(:(@paged foo.y[] == 2.5))

pv = PagedVector{Foo}(3)
pv[2] = Foo(2, 2.2)
@test pv[2] == Foo(2, 2.2)
@test length(pv) == 3
pv[1] = Foo(1, 1.1)
pv[3] = Foo(3, 3.3)
# tests iteration
@test collect(pv) == [Foo(1,1.1), Foo(2,2.2), Foo(3,3.3)]

pbv = PagedBitVector(3)
pbv[2] = true
@test pbv[2] == true
pbv[1] = false
pbv[3] = false
# tests iteration
@test collect(pbv) == [false, true, false]
fill!(pbv, false)
@test collect(pbv) == [false, false, false]

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
    @paged pma.keys[] = PagedVector{K}(ptr + sizeof(PackedMemoryArray{K,V}), length)
    @paged pma.values[] = PagedVector{V}(ptr + sizeof(PackedMemoryArray{K,V}) + length*sizeof(K), length)
    @paged pma.mask[] = PagedBitVector(ptr + sizeof(PackedMemoryArray{K,V}) + length*sizeof(K) + length*sizeof(V), length)
    fill!(@paged(pma.mask[]), false)
    @paged pma.count[] = 0
    pma
end

pma = Paged{PackedMemoryArray{Int64, Float32}}(3)
@assert @paged(pma.count[]) == 0
@paged pma.keys[]
# tests fill!
@test !any(@paged pma.mask[])
# tests pointer <-> offset conversion
@test unsafe_load(convert(Ptr{UInt64}, pma.ptr), 1) == sizeof(PackedMemoryArray{Int64, Float32})

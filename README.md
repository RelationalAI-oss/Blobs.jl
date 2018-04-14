# ManualMemory

ManualMemory makes it easy to lay out complex data-structures within a single memory region. Data-structures built using this library:

* are relocatable - internal pointers are converted to offsets, so the entire memory region can be written to / read from disk or sent over the network without pointer patching
* require no deserialization - they can be directly read/written without first copying the data into a Julia-native data-structure
* require no heap allocation - field access is just pointer arithmetic and every field read/write returns an `isbits` type which can stored on the stack

This makes them ideal for implementing out-of-core data-structures or for DMA to co-processors.

WARNING: This library is currently not memory-safe. Improper usage can cause segfaults or memory corruption. Upcoming versions will fix this.

## Usage

Acquire a `Ptr{Void}` from somewhere:

``` julia
julia> p = Libc.malloc(20)
Ptr{Void} @0x0000000002a2c070
```

We can interpret this pointer as any `isbits` Julia struct:

``` julia
julia> struct Foo
       x::Int64
       y::Bool
       end

julia> m = Manual{Foo}(p)
ManualMemory.Manual{Foo}(Ptr{Void} @0x0000000002a2c070)
```

Use the `@a` (for address) macro to obtain pointers to the fields of this struct:

``` julia
julia> @a m.x
ManualMemory.Manual{Int64}(Ptr{Void} @0x0000000002a2c070)

julia> @a m.y
ManualMemory.Manual{Bool}(Ptr{Void} @0x0000000002a2c078)
```

Or the `@v` (for value) macro to dereference those pointers:

``` julia
julia> @v m.x
44307392

julia> @v m.y
true

julia> y = @a m.y
ManualMemory.Manual{Bool}(Ptr{Void} @0x0000000002a2c078)

julia> @v y
true
```

The `@v` macro also allows setting the value of a pointer:

``` julia
julia> @v m.y = false
false

julia> @v m.y
false

julia> x = @a m.x
ManualMemory.Manual{Int64}(Ptr{Void} @0x0000000002a2c070)

julia> @v x = 42
Ptr{Int64} @0x0000000002a2c070

julia> @v x
42

julia> @v m.x
42
```

The data-structures in this module can be nested arbitrarily:

``` julia
julia> struct PackedMemoryArray{K,V}
            keys::ManualVector{K}
            values::ManualVector{V}
            mask::ManualBitVector
            count::Int
            #...other stuff
       end

julia> function Manual{PackedMemoryArray{K,V}}(length::Int64) where {K,V}
           size = sizeof(PackedMemoryArray{K,V}) + length*sizeof(K) + length*sizeof(V) + Int64(ceil(length/8))
           ptr = Libc.malloc(size)
           pma = Manual{PackedMemoryArray{K,V}}(ptr)
           @v pma.keys = ManualVector{K}(ptr + sizeof(PackedMemoryArray{K,V}), length)
           @v pma.values = ManualVector{V}(ptr + sizeof(PackedMemoryArray{K,V}) + length*sizeof(K), length)
           @v pma.mask = ManualBitVector(ptr + sizeof(PackedMemoryArray{K,V}) + length*sizeof(K) + length*sizeof(V), length)
           fill!((@v pma.mask), false)
           @v pma.count = 0
           pma
       end

julia> pma = Manual{PackedMemoryArray{Int64, Float32}}(3)
ManualMemory.Manual{PackedMemoryArray{Int64,Float32}}(Ptr{Void} @0x00000000033e4580)

julia> @v pma.count
0

julia> @v pma.mask
3-element ManualMemory.ManualBitVector:
 false
 false
 false

julia> @v pma.mask[1] = true
Ptr{UInt64} @0x00000000033e45dc

julia> @v pma.mask
3-element ManualMemory.ManualBitVector:
  true
 false
 false
```

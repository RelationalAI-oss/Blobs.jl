# Blobs

Blobs makes it easy to lay out complex data-structures within a single memory region. Data-structures built using this library:

* are relocatable - internal pointers are converted to offsets, so the entire memory region can be written to / read from disk or sent over the network without pointer patching
* require no deserialization - they can be directly read/written without first copying the data into a Julia-native data-structure
* require no heap allocation - field access is just pointer arithmetic and every field read/write returns an `isbits` type which can stored on the stack

This makes them ideal for implementing out-of-core data-structures or for DMA to co-processors.

## Safety

This library does not protect against:

* giving an incorrect length when creating a `Blob`
* using a `Blob` after freeing the underlying allocation

Apart from that, all other operations are safe. User error or invalid data can cause `AssertionError` but cannot segfault the program or modify memory outside the blob.

## Usage

Acquire a `Ptr{Void}` from somewhere:

``` julia
julia> struct Foo
       x::Int64
       y::Bool
       end

julia> p = Libc.malloc(sizeof(Foo))
Ptr{Void} @0x0000000006416020
```

We can interpret this pointer as any `isbits` Julia struct:

``` julia
julia> foo = Blob{Foo}(p, UInt64(0), UInt64(sizeof(Foo)))
Blobs.Blob{Foo}(Ptr{Void} @0x0000000004de87c0, 0x0000000000000000, 0x0000000000000010)
```

(See `Blobs.malloc_and_init` for a safer way to create a fresh blob).

Use the `@blob` macro to obtain references to the fields of this struct:

``` julia
julia> @blob foo.x
Blobs.Blob{Int64}(Ptr{Void} @0x0000000004de87c0, 0x0000000000000000, 0x0000000000000010)

julia> @blob foo.y
Blobs.Blob{Bool}(Ptr{Void} @0x0000000004de87c0, 0x0000000000000008, 0x0000000000000010)
```

Or to dereference those references:

``` julia
julia> @blob foo[]
Foo(114974496, true)

julia> @blob foo.x[]
114974496

julia> @blob foo.y[]
true

julia> y = @blob foo.y
Blobs.Blob{Bool}(Ptr{Void} @0x0000000004de87c0, 0x0000000000000008, 0x0000000000000010)

julia> @blob y[]
true
```

The `@blob` macro also allows setting the value of a reference:

``` julia
julia> @blob foo.y[] = false
false

julia> @blob foo.y[]
false

julia> x = @blob foo.x
Blobs.Blob{Int64}(Ptr{Void} @0x0000000004de87c0, 0x0000000000000000, 0x0000000000000010)

julia> @blob x[] = 42
42

julia> @blob x[]
42

julia> @blob foo.x[]
42
```

The various data-structures provided can be nested arbitrarily. See the [tests](https://github.com/RelationalAI-oss/Blobs.jl/) for examples.

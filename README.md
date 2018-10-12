# Blobs

Blobs makes it easy to lay out complex data-structures within a single memory region. Data-structures built using this library:

* are relocatable - internal pointers are converted to offsets, so the entire memory region can be written to / read from disk or sent over the network without pointer patching
* require no deserialization - they can be directly read/written without first copying the data into a Julia-native data-structure
* require no additional heap allocation - field access is just pointer arithmetic and every field read/write returns an `isbitstype` type which can stored on the stack

This makes them ideal for implementing out-of-core data-structures or for DMA to co-processors.

## Safety

This library does not protect against:

* giving an incorrect length when creating a `Blob`
* using a `Blob` after freeing the underlying allocation

Apart from that, all other operations are safe. User error or invalid data can cause `AssertionError` or `BoundsError` but cannot segfault the program or modify memory outside the blob.

## Usage

Acquire a `Ptr{Nothing}` from somewhere:

``` julia
julia> struct Foo
       x::Int64
       y::Bool
       end

julia> p = Libc.malloc(sizeof(Foo))
Ptr{Nothing} @0x0000000006416020
```

We can interpret this pointer as any `isbitstype` Julia struct:

``` julia
julia> foo = Blob{Foo}(p, 0, sizeof(Foo))
Blobs.Blob{Foo}(Ptr{Nothing} @0x0000000004de87c0, 0, 16)
```

(See `Blobs.malloc_and_init` for a safer way to create a fresh blob).

We can access references to fields of Foo using the fieldnames directly:

``` julia
julia> foo.x
Blobs.Blob{Int64}(Ptr{Nothing} @0x0000000004de87c0, 0, 16)

julia> foo.y
Blobs.Blob{Bool}(Ptr{Nothing} @0x0000000004de87c0, 8, 16)
```

And use `[]` to derefence Blobs:

``` julia
julia> foo[]
Foo(114974496, true)

julia> foo.x[]
114974496

julia> foo.y[]
true

julia> y = foo.y
Blobs.Blob{Bool}(Ptr{Nothing} @0x0000000004de87c0, 8, 16)

julia> y[]
true
```

Similarly for setting values:

``` julia
julia> foo[] = Foo(12, true)
Foo(12, true)

julia> foo[]
Foo(12, true)

julia> foo.y[] = false
false

julia> foo.y[]
false

julia> x = foo.x
Blobs.Blob{Int64}(Ptr{Nothing} @0x0000000004de87c0, 0, 16)

julia> x[] = 42
42

julia> x[]
42

julia> foo.x[]
42
```

The various data-structures provided can be nested arbitrarily. See the [tests](https://github.com/RelationalAI-oss/Blobs.jl/blob/master/test/runtests.jl) for examples.


## Compatibility with Previous Versions

In the previous versions of this library, two macros `@v` and `@` were used and we keep them for compatibility reasons. This macros bypass some of the bound-checkings and safety measures that are in-place in the normal usage of `Blobs`. In this section, we will introduce their usage.

Assume that we have the following `Foo` struct:

``` julia
julia> struct Foo
       x::Int64
       y::Bool
       end

julia> m = Blobs.malloc_and_init(Foo)
Blob{Foo}(Ptr{Nothing} @0x00007fa0b84234e0, 0, 9)
```

Use the `@a` (for address) macro to obtain pointers to the fields of this struct:

``` julia
julia> @a m.x
Blob{Int64}(Ptr{Nothing} @0x00007fa0b84234e0, 0, 9)

julia> @a m.y
Blob{Bool}(Ptr{Nothing} @0x00007fa0b84234e0, 8, 9)
```

Or the `@v` (for value) macro to dereference those pointers:

``` julia
julia> @v m.x
44307392

julia> @v m.y
false

julia> y = @a m.y
Blob{Bool}(Ptr{Nothing} @0x00007fa0b84234e0, 8, 9)

julia> @v y
false
```

The `@v` macro also allows setting the value of a pointer:

``` julia
julia> @v m.y = true
true

julia> @v m.y
true

julia> x = @a m.x
Blob{Int64}(Ptr{Nothing} @0x00007fa0b84234e0, 0, 9)

julia> @v x = 42
42

julia> @v x
42

julia> @v m.x
42
```

Also in this case, data-structures can be nested arbitrarily. See the [compat-tests](https://github.com/RelationalAI-oss/Blobs.jl/blob/master/test/compat-tests.jl) for examples.
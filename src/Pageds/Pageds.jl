module Pageds

using Delve.Util

abstract type AbstractPaged{T} end

"""
A pointer to a `T` in some manually managed region of memory.

TODO do we want to also keep the page address/size in here? If we complicate the loading code a little we could avoid writing it to the page, so it would only exist on the stack.
"""
struct Paged{T} <: AbstractPaged{T}
    ptr::Ptr{Void}

    function Paged{T}(ptr::Ptr{Void}) where {T}
        @assert isbits(T)
        new(ptr)
    end
end

get_ptr(paged::Paged{T}) where {T} = paged.ptr

"Allocate `size` bytes for an unintialized Paged{T}"
Paged{T}(size::Integer) where {T} = Paged{T}(Libc.malloc(size))

"Allocate `sizeof(T)` bytes for an unintialized Paged{T}"
Paged{T}() where {T} = Paged{T}(sizeof(T))

function rewrite_address(expr)
    if !(expr isa Expr)
        esc(expr)
    elseif expr.head == :.
        (object, field) = expr.args
        if field isa QuoteNode
            fieldname = field.value
        elseif field isa Expr && field.head == :quote
            fieldname = field.args[1]
        else
            error("Impossible?")
        end
        :(get_address($(rewrite_address(object)), $(Val{fieldname})))
    elseif expr.head == :ref
        object = expr.args[1]
        :(get_address($(rewrite_address(object)), $(map(esc, expr.args[2:end])...)))
    elseif expr.head == :macrocall
        rewrite_address(macroexpand(expr))
    else
        error("Don't know how to compute address for $expr")
    end
end

"""
    @a paged.x[2].y

Get a `Paged` pointing at the *address* of `paged.x[2].y`.
"""
macro a(expr)
    rewrite_address(expr)
end

function rewrite_value(expr)
    if (expr isa Expr) && (expr.head == :(=))
        if length(expr.args) == 2
            :(unsafe_store!($(rewrite_address(expr.args[1])), $(esc(expr.args[2]))))
        else
            error("Don't know how to compute assignment $expr")
        end
    else
        :(unsafe_load($(rewrite_address(expr))))
    end
end

"""
    @v paged.x[2].y

Get the *value* at `paged.x[2].y`.

    @v paged.x[2].y = 42

Set the *value* at `paged.x[2].y`.

NOTE macros bind tightly, so:

    # invalid syntax
    @v paged.x[2].y < 42

    # valid syntax
    (@v paged.x[2].y) < 42
"""
macro v(expr)
    rewrite_value(expr)
end

@generated function get_address(paged::AbstractPaged{T}, ::Type{Val{field}}) where {T, field}
    i = findfirst(fieldnames(T), field)
    @assert i != 0 "$T has no field $field"
    quote
        $(Expr(:meta, :inline))
        Paged{$(fieldtype(T, i))}(get_ptr(paged) + $(fieldoffset(T, i)))
    end
end

@generated function Base.unsafe_load(paged::AbstractPaged{T}) where {T}
    if isempty(fieldnames(T))
        # is a primitive type
        quote
            $(Expr(:meta, :inline))
            unsafe_load(convert(Ptr{T}, get_ptr(paged)))
        end
    else
        # is a composite type - recursively load its fields
        # so that specializations of this method can hook in and alter loading
        $(Expr(:meta, :inline))
        Expr(:new, T, @splice (i, field) in enumerate(fieldnames(T)) quote
            unsafe_load(get_address(paged, $(Val{field})))
        end)
    end
end

# can write to a Paged{T} using the syntax p[] = ...
@generated function Base.unsafe_store!(paged::AbstractPaged{T}, value::T) where {T}
    if isempty(fieldnames(T))
        # is a primitive type
        quote
            $(Expr(:meta, :inline))
            unsafe_store!(convert(Ptr{T}, get_ptr(paged)), value)
        end
    else
        # is a composite type - recursively store its fields
        # so that specializations of this method can hook in and alter storing
        quote
            $(Expr(:meta, :inline))
            $(@splice (i, field) in enumerate(fieldnames(T)) quote
                unsafe_store!(get_address(paged, $(Val{field})), value.$field)
            end)
        end
    end
end

# if the value is the wrong type, try to convert it (just like setting a field normally)
@inline function Base.unsafe_store!(paged::AbstractPaged{T}, value) where {T}
    unsafe_store!(paged, convert(T, value))
end

# pointers to other parts of the page need to be converted into offsets

@inline function Base.unsafe_load(paged::AbstractPaged{Paged{T}}) where {T}
    offset = unsafe_load(Paged{UInt64}(paged.ptr))
    Paged{T}(get_ptr(paged) + offset)
end

@inline function Base.unsafe_store!(paged::AbstractPaged{Paged{T}}, value::Paged{T}) where {T}
    offset = value.ptr - get_ptr(paged)
    unsafe_store!(Paged{UInt64}(get_ptr(paged)), offset)
end

"""
    is_paged_type(x::Type{T}) where {T}

Returns true if the given type is not Paged
"""
is_paged_type(x::Type{T}) where {T} = false
is_paged_type(x::Type{Paged{T}}) where {T} = true

include("paged_vectors.jl")
include("paged_bit_vectors.jl")
include("paged_strings.jl")
include("packed_memory_array.jl")

"""
Extracts the field initializer data from `Val` type
"""
function fieldinfo(size_init::Type{Type{Val{fieldinit}}}) where {fieldinit}
    fieldinit
end

"""
This method determines the number of bytes required to store the bits of a type
{T} that are pointed at using the paged fields of {T}
"""
function pageddatasize(x::Type{T}, length::Int64) where {T}
    total = 0
    for field in fieldnames(T)
        fieldtp = fieldtype(T, field)
        if is_paged_type(fieldtp)
            total += pageddatasize(fieldtp, length)
        end
    end
    total
end

function pageddatasize(x::Type{Paged{T}}, length::Int64) where {T}
    total = sizeof(T) + pageddatasize(T, length)
end

"""
Calculates the number of bytes required for allocating a `Paged` field of a
type that consists of one or more `Paged` data memebers
"""
function pagedfieldsize(::Type{T}, fieldinit::Pair{Symbol,Int64}) where {T}
    (field, fieldlen) = fieldinit
    i = findfirst(fieldnames(T), field)
    @assert i != 0 "$T has no field $field"
    fieldtp = fieldtype(T, i)
    @assert is_paged_type(fieldtp) "$T.$field is not a paged field. Only paged fields should be in the initializer list."
    pageddatasize(fieldtp, fieldlen)
end

function pagedfieldsize(::Type{Paged{T}}, fieldinit::Pair{Symbol,Int64}) where {T}
    pagedfieldsize(T, fieldinit)
end

"""
Calculates the number of bytes required for allocating a
type that consists of one or more `Paged` data memebers
"""
function pagedsize(::Type{T}, field_inits::Dict{Symbol,Int64}) where {T}
    size_tp = sizeof(T)
    total_size = size_tp
    for field_init in field_inits
        total_size += pagedfieldsize(T, field_init)
    end
    total_size
end

"""
Initalizes a type that is composed of one or more `Paged` data members.

It fixes the pointers to these `Paged` fields to point into the right memory location.

This method returns a tuple of expressions:
  1. Instance initialization expression (that returns the instance itself at the end)
  2. A pointer to the end of current field. It determines where the next field (if any) exists
"""
function pagedinit(::Type{T}, inst_block::Expr, start::UInt64, fieldinit::Pair{Symbol,Int64}) where {T}
    (field, fieldlen) = fieldinit
    fieldsize = pagedfieldsize(T, fieldinit)
    i = findfirst(fieldnames(T), field)
    @assert i != 0 "$T has no field $field"
    fieldtp = fieldtype(T, i)
    (if is_paged_type(fieldtp)
        quote
            instance = $inst_block
            @v instance.$field = $fieldtp(instance.ptr + $start, $fieldlen)
            instance
        end
    else
        quote
            instance = $inst_block
            instance.$field = $fieldtp(instance.ptr + $start, $fieldlen)
            instance
        end
    end, start + fieldsize)
end

function pagedwire(::Type{T}, alloc_page::Expr, field_inits::Dict{Symbol,Int64}) where {T}
    size_tp = sizeof(T)

    start = UInt64(size_tp)
    
    wired_block = quote
        $alloc_page
    end
    
    for field in fieldnames(T)
        if is_paged_type(fieldtype(T, field))
            @assert haskey(field_inits, field) "$T.$field is not in the initializer list. All the paged fields should be present in the initializer list."
            (wired_block, start) = pagedinit(T, wired_block, start, field => field_inits[field])
        end
    end
    
    wired_block
end

@generated function pagedwire(alloc_page::Paged{T}, size_inits...) where {T}
    field_inits = Dict{Symbol,Int64}(((field, fieldlen) = fieldinfo(size_init); field => fieldlen) for size_init in size_inits)
    alloc_page_block = quote
        alloc_page
    end
    pagedwire(T, alloc_page_block, field_inits)
end

"""
    pagedalloc(tp::Type{T}, alloc::Function, size_inits...) where {T}

Allocates and correctly initializes the pointers in a type that is composed
of one or more `Paged` data members.

```@example
using Delve.Pageds # hide

"Sample data structure, mixing primitive and paged fields"
struct Foo
    a::Int
    b::Pageds.PagedBitVector
    c::Bool
    d::Pageds.PagedVector{Float64}
end

#
# Desired layout of Foo in memory:
#
# ┌───┬─────┐
# │ a │ ... │
# │ b │  ■──┼───┐
# │ c │ ... │   │
# │ d |  ■──┼───┼──┐
# ├───┴─────┤   │  │
# │ bs ...  │ <─┘  │
# │         │      │
# │         │      │
# ├ ─ ─ ─ ─ ┤      │
# │ ds ...  │ <────┘
# │         │
# └─────────┘
#

# Allocate a new `Foo` with `a` uninitialized, `b` of length `10`, `c` with value `false`, `d` of length `20`
foo = pagedalloc(Foo, Libc.malloc, Val{(:b, 10)}, Val{(:d,20)})
@v foo.c = false

nothing # hide
```

# Arguments
- `tp`: the target type that is composed of one or more `Paged` data members
- `alloc`: the allocation function that accepts an `Integer` parameter. You can use `Libc.malloc` or your own function if you want to do custom memory manegement.
- `size_inits`: the list of size initializer. You can pass several argments of type `Val{Tuple{Symbol, Int64}}`. This list should only include all the `Paged` fields. Each argument is a tuple of field `Symbol` and its `length` argument wrapped inside a `Val`.
"""
@generated function pagedalloc(::Type{T}, alloc::Function, size_inits...) where {T}
    field_inits = Dict{Symbol,Int64}(((field, fieldlen) = fieldinfo(size_init); field => fieldlen) for size_init in size_inits)

    total_size = pagedsize(T, field_inits)
    
    alloc_page_block = quote
        alloc_ptr = alloc($total_size)
        Paged{T}(alloc_ptr)
    end
    
    pagedwire(T, alloc_page_block, field_inits)
end

export Paged, PagedVector, PagedBitVector, PagedString, PackedMemoryArray, @a, @v
export pagedsize, pagedwire, pagedalloc

end

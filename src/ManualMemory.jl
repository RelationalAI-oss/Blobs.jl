module ManualMemory

macro splice(iterator, body)
  @assert iterator.head == :call
  @assert iterator.args[1] == :in
  Expr(:..., :(($(esc(body)) for $(esc(iterator.args[2])) in $(esc(iterator.args[3])))))
end

"""
A pointer to a `T` in some manually managed region of memory.
"""
# TODO do we want to also keep the page address/size in here? If we complicate the loading code a little we could avoid writing it to the page, so it would only exist on the stack.
struct Manual{T}
    ptr::Ptr{Void}

    function Manual{T}(ptr::Ptr{Void}) where {T}
        @assert isbits(T)
        new(ptr)
    end
end

get_ptr(man::Manual{T}) where {T} = man.ptr

"Allocate `size` bytes for an unintialized Manual{T}"
Manual{T}(size::Integer) where {T} = Manual{T}(Libc.malloc(size))

"Allocate `sizeof(T)` bytes for an unintialized Manual{T}"
Manual{T}() where {T} = Manual{T}(sizeof(T))

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
    @a man.x[2].y

Get a `Manual` pointing at the *address* of `man.x[2].y`.
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
    @v man.x[2].y

Get the *value* at `man.x[2].y`.

    @v man.x[2].y = 42

Set the *value* at `man.x[2].y`.

NOTE macros bind tightly, so:

    # invalid syntax
    @v man.x[2].y < 42

    # valid syntax
    (@v man.x[2].y) < 42
"""
macro v(expr)
    rewrite_value(expr)
end

function get_address(man::Manual{Manual{T}}, ::Type{Val{field}}) where {T, field}
    get_address(Manual{T}(get_ptr(man)), Val{field})
end

@generated function get_address(man::Manual{T}, ::Type{Val{field}}) where {T, field}
    i = findfirst(fieldnames(T), field)
    @assert i != 0 "$T has no field $field"
    quote
        $(Expr(:meta, :inline))
        Manual{$(fieldtype(T, i))}(get_ptr(man) + $(fieldoffset(T, i)))
    end
end

@generated function Base.unsafe_load(man::Manual{T}) where {T}
    if isempty(fieldnames(T))
        # is a primitive type
        quote
            $(Expr(:meta, :inline))
            unsafe_load(convert(Ptr{T}, get_ptr(man)))
        end
    else
        # is a composite type - recursively load its fields
        # so that specializations of this method can hook in and alter loading
        $(Expr(:meta, :inline))
        Expr(:new, T, @splice (i, field) in enumerate(fieldnames(T)) quote
            unsafe_load(get_address(man, $(Val{field})))
        end)
    end
end

# can write to a Manual{T} using the syntax p[] = ...
@generated function Base.unsafe_store!(man::Manual{T}, value::T) where {T}
    if isempty(fieldnames(T))
        # is a primitive type
        quote
            $(Expr(:meta, :inline))
            unsafe_store!(convert(Ptr{T}, get_ptr(man)), value)
        end
    else
        # is a composite type - recursively store its fields
        # so that specializations of this method can hook in and alter storing
        quote
            $(Expr(:meta, :inline))
            $(@splice (i, field) in enumerate(fieldnames(T)) quote
                unsafe_store!(get_address(man, $(Val{field})), value.$field)
            end)
        end
    end
end

# if the value is the wrong type, try to convert it (just like setting a field normally)
@inline function Base.unsafe_store!(man::Manual{T}, value) where {T}
    unsafe_store!(man, convert(T, value))
end

# pointers to other parts of the region need to be converted into offsets

@inline function Base.unsafe_load(man::Manual{Manual{T}}) where {T}
    offset = unsafe_load(Manual{UInt64}(man.ptr))
    Manual{T}(get_ptr(man) + offset)
end

@inline function Base.unsafe_store!(man::Manual{Manual{T}}, value::Manual{T}) where {T}
    offset = value.ptr - get_ptr(man)
    unsafe_store!(Manual{UInt64}(get_ptr(man)), offset)
end

"""
    is_manual_type(x::Type{T}) where {T}

Returns true if the given type is a Manual type
"""
is_manual_type(x::Type{T}) where {T} = false
is_manual_type(x::Type{Manual{T}}) where {T} = true

include("manual_vectors.jl")
include("manual_bit_vectors.jl")
include("manual_strings.jl")

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
function manual_datasize(x::Type{T}, length::Int64) where {T}
    total = 0
    for field in fieldnames(T)
        fieldtp = fieldtype(T, field)
        if is_manual_type(fieldtp)
            total += manual_datasize(fieldtp, length)
        end
    end
    total
end

function manual_datasize(x::Type{Manual{T}}, length::Int64) where {T}
    total = sizeof(T) + manual_datasize(T, length)
end

"""
Calculates the number of bytes required for allocating a `Manual` field of a
type that consists of one or more `Manual` data memebers
"""
function manual_fieldsize(::Type{T}, fieldinit::Pair{Symbol,Int64}) where {T}
    (field, fieldlen) = fieldinit
    i = findfirst(fieldnames(T), field)
    @assert i != 0 "$T has no field $field"
    fieldtp = fieldtype(T, i)
    @assert is_manual_type(fieldtp) "$T.$field is not a paged field. Only paged fields should be in the initializer list."
    manual_datasize(fieldtp, fieldlen)
end

function manual_fieldsize(::Type{Manual{T}}, fieldinit::Pair{Symbol,Int64}) where {T}
    manual_fieldsize(T, fieldinit)
end

"""
Calculates the number of bytes required for allocating a
type that consists of one or more `Manual` data members
"""
function manual_size(::Type{T}, field_inits::Dict{Symbol,Int64}) where {T}
    size_tp = sizeof(T)
    total_size = size_tp
    for field_init in field_inits
        total_size += manual_fieldsize(T, field_init)
    end
    total_size
end

"""
Initalizes a type that is composed of one or more `Manual` data members.

It fixes the pointers to these `Manual` fields to point into the right memory location.

This method returns a tuple of expressions:
  1. Instance initialization expression (that returns the instance itself at the end)
  2. A pointer to the end of current field. It determines where the next field (if any) exists
"""
function manual_init(::Type{T}, inst_block::Expr, start::UInt64, fieldinit::Pair{Symbol,Int64}) where {T}
    (field, fieldlen) = fieldinit
    fieldsize = manual_fieldsize(T, fieldinit)
    i = findfirst(fieldnames(T), field)
    @assert i != 0 "$T has no field $field"
    fieldtp = fieldtype(T, i)
    (if is_manual_type(fieldtp)
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

function manual_wire(::Type{T}, alloc_page::Expr, field_inits::Dict{Symbol,Int64}) where {T}
    size_tp = sizeof(T)

    start = UInt64(size_tp)

    wired_block = quote
        $alloc_page
    end

    for field in fieldnames(T)
        if is_manual_type(fieldtype(T, field))
            @assert haskey(field_inits, field) "$T.$field is not in the initializer list. All the paged fields should be present in the initializer list."
            (wired_block, start) = manual_init(T, wired_block, start, field => field_inits[field])
        end
    end

    wired_block
end

@generated function manual_wire(alloc_page::Manual{T}, size_inits...) where {T}
    field_inits = Dict{Symbol,Int64}(((field, fieldlen) = fieldinfo(size_init); field => fieldlen) for size_init in size_inits)
    alloc_page_block = quote
        alloc_page
    end
    manual_wire(T, alloc_page_block, field_inits)
end

"""
    manualalloc(tp::Type{T}, alloc::Function, size_inits...) where {T}

Allocates and correctly initializes the pointers in a type that is composed
of one or more `Manual` data members.

```@example
using ManualMemory # hide

"Sample data structure, mixing primitive and manual fields"
struct Foo
    a::Int
    b::ManualBitVector
    c::Bool
    d::ManualVector{Float64}
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
foo = manualalloc(Foo, Libc.malloc, Val{(:b, 10)}, Val{(:d,20)})
@v foo.c = false

nothing # hide
```

# Arguments
- `tp`: the target type that is composed of one or more `Manual` data members
- `alloc`: the allocation function that accepts an `Integer` parameter. You can use `Libc.malloc` or your own function if you want to do custom memory manegement.
- `size_inits`: the list of size initializer. You can pass several argments of type `Val{Tuple{Symbol, Int64}}`. This list should only include all the `Manual` fields. Each argument is a tuple of field `Symbol` and its `length` argument wrapped inside a `Val`.
"""
@generated function manual_alloc(::Type{T}, alloc::Function, size_inits...) where {T}
    field_inits = Dict{Symbol,Int64}(((field, fieldlen) = fieldinfo(size_init); field => fieldlen) for size_init in size_inits)

    total_size = manual_size(T, field_inits)

    alloc_page_block = quote
        alloc_ptr = alloc($total_size)
        Manual{T}(alloc_ptr)
    end

    manual_wire(T, alloc_page_block, field_inits)
end

export Manual, ManualVector, ManualBitVector, ManualString, @a, @v
export manual_size, manual_wire, manual_alloc, maxlength

end

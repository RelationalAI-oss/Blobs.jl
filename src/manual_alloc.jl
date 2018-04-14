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
@generated function manual_alloc(::Type{T}, alloc::Function, field_lengths...) where {T}
    unpack(::Type{Type{Val{field_length}}}) where {field_length} = field_length
    field_lengths = Dict(map(unpack, field_lengths))
    sized_fields = Set((field for field in fieldnames(T) if method_exists(alloc_size, Tuple{Type{fieldtype(T, field)}, Int64})))
    
    for (field, length) in field_lengths
        @assert field in fieldnames(T) "$T has no field $field"
        @assert field in sized_fields "Field $field of $T does not implement alloc_size and so can't be given a length"
        @assert length isa Integer "Invalid length $length for field $field of $T"
    end
    for field in sized_fields
        @assert haskey(field_lengths, field) "Field $field of $T implements alloc_size but has not been given a length"
    end
    
    offset = sizeof(T)
    body = []
    for (field, length) in field_lengths
        push!(body, quote
            @v value.$field = $(fieldtype(T, field))(ptr + $offset, $length)
        end)
        offset += alloc_size(fieldtype(T, field), length)
    end
    quote
        ptr = alloc($offset)
        value = Manual{T}(ptr)
        $(body...)
        value
    end
end


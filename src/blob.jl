"""
A pointer to a `T` stored inside a Blob.
"""
struct Blob{T}
    base::Ptr{Nothing}
    offset::Int64
    limit::Int64

    function Blob{T}(base::Ptr{Nothing}, offset::Int64, limit::Int64) where {T}
        @assert isbitstype(T)
        new(base, offset, limit)
    end
end

function Blob{T}(blob::Blob) where T
    Blob{T}(getfield(blob, :base), getfield(blob, :offset), getfield(blob, :limit))
end

function assert_same_allocation(blob1::Blob, blob2::Blob)
    @assert getfield(blob1, :base) == getfield(blob2, :base) "These blobs do not share the same allocation: $blob1 - $blob2"
end

function Base.pointer(blob::Blob{T}) where T
    convert(Ptr{T}, getfield(blob, :base) + getfield(blob, :offset))
end

function Base.:+(blob::Blob{T}, offset::Integer) where T
    Blob{T}(getfield(blob, :base), getfield(blob, :offset) + offset, getfield(blob, :limit))
end

function Base.:-(blob1::Blob, blob2::Blob)
    assert_same_allocation(blob1, blob2)
    getfield(blob1, :offset) - getfield(blob2, :offset)
end

@inline function boundscheck(blob::Blob{T}) where T
    @boundscheck begin
        if (getfield(blob, :offset) < 0) || (getfield(blob, :offset) + self_size(T) > getfield(blob, :limit))
            throw(BoundsError(blob))
        end
    end
end

Base.@propagate_inbounds function Base.getindex(blob::Blob{T}) where T
    boundscheck(blob)
    unsafe_load(blob)
end

# Compute the size of a Blob{T}, by recursively summing the sizes of
# its fields.  Note that the Blob size of T may be smaller
# than the Julia layout of T, since we do not align fields (see note
# at gen_unsafe_store!, below.)
function compute_self_size(::Type{T})::Int where T
    if isempty(T.types)
        sizeof(T)
    else
        mapreduce(compute_self_size, +, T.types)
    end
end

# TV: I don't understand this
# patch pointers on the fly during load/store!
function compute_self_size(::Type{Blob{T}})::Int where T
    sizeof(Int64)
end

"""
    self_size(::Type{T}, args...) where {T}

The number of bytes needed to allocate `T` itself.

Defaults to `sizeof(T)`.
"""
@generated function self_size(::Type{T}) where T
    @assert isconcretetype(T)
    quote
        $(Expr(:meta, :inline))
        $(compute_self_size(T))
    end
end

function blob_offset(::Type{T}, i::Int) where {T}
    +(0, @splice j in 1:(i-1) begin
        self_size(fieldtype(T, j))
    end)
end

@generated function Base.getindex(blob::Blob{T}, ::Type{Val{field}}) where {T, field}
    i = findfirst(isequal(field), fieldnames(T))
    @assert i != nothing "$T has no field $field"
    quote
        $(Expr(:meta, :inline))
        Blob{$(fieldtype(T, i))}(blob + $(blob_offset(T, i)))
    end
end

Base.@propagate_inbounds function Base.setindex!(blob::Blob{T}, value::T) where T
    boundscheck(blob)
    unsafe_store!(blob, value)
end

# if the value is the wrong type, try to convert it (just like setting a field normally)
Base.@propagate_inbounds function Base.setindex!(blob::Blob{T}, value) where T
    setindex!(blob, convert(T, value))
end

# Generate code to retrieve the contents of a Blob{T} as an object of type T.
# For Complex{Float64}, returns:
# :(%new(Complex{Float64},
#     unsafe_load(convert(Ptr{Float64}, blobptr + 0)),
#     unsafe_load(convert(Ptr{Float64}, blobptr + 8))))
# For Date, returns:
# :(%new(Date,
#     %new(Dates.UTInstant{Day},
#         %new(Day, unsafe_load(convert(Ptr{Int64}, blobptr + 0))))))
function gen_unsafe_load(layout_offset::Int, T::DataType)::Expr
    if isempty(fieldnames(T))
        :(unsafe_load(convert(Ptr{$(T)}, blobptr + $(layout_offset))))
    else
        loads = []
        pos = layout_offset
        for fieldtype in T.types
            push!(loads, gen_unsafe_load(pos, fieldtype))
            pos += self_size(fieldtype)
        end
        Expr(:new, T, loads...)
    end
end

@generated function Base.unsafe_load(blob::Blob{T}) where {T}
    quote
        $(Expr(:meta, :inline))
        blobptr = getfield(blob, :base) + getfield(blob, :offset)
        $(gen_unsafe_load(0, T))
    end
end

# Generate code to write the contents an object of type T into a Blob{T}.
# For Complex{Float64}, we generate:
#    unsafe_store!(convert(Ptr{Float64}, blobptr + 0), value.re))
#    unsafe_store!(convert(Ptr{Float64}, blobptr + 8), value.im))
# Note that the blob layout is not the same as the layout of a Julia struct,
# because of padding and alignment.  For example:
#     struct Foo
#         x::Int8
#         y::Int64
#     end
# has sizeof(Foo)=16, but the blob has size 9.  This means that some fields
# may be unaligned in the blob layout.  E.g. for x::Tuple{Int8,Float64,Int32}:
#    unsafe_store!(convert(Ptr{Int8}, blobptr + 0), x[1])
#    unsafe_store!(convert(Ptr{Float64}, blobptr + 1), x[2])
#    unsafe_store!(convert(Ptr{Int16}, blobptr + 9), x[3])
# This is intentional, so the blob representation is compact.
function gen_unsafe_store!(code::Vector{Any}, layout_offset::Int, T::DataType, struct_path)
    if isempty(fieldnames(T))
        push!(code, :(unsafe_store!(convert(Ptr{$(T)}, blobptr + $(layout_offset)), $(struct_path))))
    else
        if T <: Tuple
            # For x::Tuple{Int,Int}, we access fields as x[1], x[2]
            get_struct_path = (struct_path, i, field) -> :($(struct_path)[$(i)])
        else
            # For x::Complex{T}, we access fields as x.re, x.im
            get_struct_path = (struct_path, i, field) -> :($(struct_path).$(field))
        end
        pos = layout_offset
        for (i, field) in enumerate(fieldnames(T))
            fieldtype = T.types[i]
            gen_unsafe_store!(code, layout_offset+pos, fieldtype, get_struct_path(struct_path, i, field))
            pos += self_size(fieldtype)
        end
    end
    nothing
end

@generated function Base.unsafe_store!(blob::Blob{T}, value::T) where {T}
    code = []
    gen_unsafe_store!(code, 0, T, :value)
    quote
        $(Expr(:meta, :inline))
        blobptr = getfield(blob, :base) + getfield(blob, :offset)
        $(code...)
        value
    end
end

# if the value is the wrong type, try to convert it (just like setting a field normally)
function Base.unsafe_store!(blob::Blob{T}, value) where {T}
    unsafe_store!(blob, convert(T, value))
end

# syntax sugar

function Base.propertynames(::Blob{T}, private=false) where T
    fieldnames(T)
end

function Base.getproperty(blob::Blob{T}, field::Symbol) where T
    getindex(blob, Val{field})
end

function Base.setproperty!(blob::Blob{T}, field::Symbol, value) where T
    setindex!(blob, Val{field}, value)
end

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
        :(getindex($(rewrite_address(object)), $(Val{fieldname})))
    elseif expr.head == :ref
        object = expr.args[1]
        :(getindex($(rewrite_address(object)), $(map(esc, expr.args[2:end])...)))
    elseif expr.head == :macrocall
        rewrite_address(macroexpand(expr))
    else
        error("Don't know how to compute address for $expr")
    end
end

"""
    @a blob.x[2].y

Get a `Blob` pointing at the *address* of `blob.x[2].y`.
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
    @v blob.x[2].y

Get the *value* at `blob.x[2].y`.

    @v blob.x[2].y = 42

Set the *value* at `blob.x[2].y`.

NOTE macros bind tightly, so:

    # invalid syntax
    @v blob.x[2].y < 42

    # valid syntax
    (@v blob.x[2].y) < 42
"""
macro v(expr)
    rewrite_value(expr)
end

@inline function Base.unsafe_load(blob::Blob{Blob{T}}) where {T}
    offset = unsafe_load(Blob{Int64}(blob))
    Blob{T}(getfield(blob, :base), getfield(blob, :offset) + offset, getfield(blob, :limit))
end

@inline function Base.unsafe_store!(blob::Blob{Blob{T}}, value::Blob{T}) where {T}
    assert_same_allocation(blob, value)
    offset = getfield(value, :offset) - getfield(blob, :offset)
    unsafe_store!(Blob{Int64}(blob), offset)
end

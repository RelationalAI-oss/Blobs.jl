"""
    alloc_size(::Type{T}, args...) where {T}

The number of additional bytes needed to allocate `T`, other than `sizeof(T)` itself.

Defaults to 0.
"""
alloc_size(::Type{T}) where T = 0

"""
    init(man::Manual{T}, args...) where T

Initialize `man`.
"""
function init(man::Manual{T}, args...) where T
    init(man.ptr + sizeof(T), man, args...)
    nothing
end

"""
    init(ptr::Ptr{Void}, man::Manual{T}, args...)::Ptr{Void} where T

Initialize `man`, where `ptr` is the beginning of the remaining free space. Must return `ptr + alloc_size(T, args...)`. Override this method to add custom initializers for your types.

The default implementation where `alloc_size(T) == 0` does nothing.
"""
function init(ptr::Ptr{Void}, man::Manual{T}) where T
    @assert alloc_size(T) == 0 "Default init cannot be used for types for which alloc_size(T) != 0"
    # TODO should we zero memory?
    ptr
end

alloc_size(::Type{Manual{T}}, args...) where T = sizeof(T) + alloc_size(T, args...)

function init(ptr::Ptr{Void}, man::Manual{Manual{T}}, args...) where T
    @v man = Manual{T}(ptr)
    t = Manual{T}(ptr)
    t_ptr = ptr + sizeof(T)
    init(t_ptr, t, args...)
end

alloc_size(::Type{ManualVector{T}}, length::Int64) where {T} = sizeof(T) * length

function init(ptr::Ptr{Void}, pv::Manual{ManualVector{T}}, length::Int64) where T
    @v pv.ptr = Manual{T}(ptr)
    @v pv.length = length
    ptr + alloc_size(ManualVector{T}, length)
end

alloc_size(::Type{ManualBitVector}, length::Int64) = UInt64(ceil(length / sizeof(UInt64)))

function init(ptr::Ptr{Void}, pv::Manual{ManualBitVector}, length::Int64)
    @v pv.ptr = Manual{UInt64}(ptr)
    @v pv.length = length
    ptr + alloc_size(ManualBitVector, length)
end

alloc_size(::Type{ManualString}, length::Int64) = length

function init(ptr::Ptr{Void}, ps::Manual{ManualString}, length::Int64)
    @v ps.ptr = Manual{UInt8}(ptr)
    @v ps.len = length
    ptr + alloc_size(ManualString, length)
end

alloc_size(::Type{ManualString}, string::Union{String, ManualString}) = string.len

function init(ptr::Ptr{Void}, ps::Manual{ManualString}, string::Union{String, ManualString})
    ptr = init(ptr, ps, string.len)
    unsafe_copy!((@v ps), string)
    ptr
end

"""
    malloc(::Type{T}, args...)::Manual{T} where T

Allocate and initialize a new `Manual{T}`.
"""
function malloc(::Type{T}, args...)::Manual{T} where T
    size = sizeof(T) + alloc_size(T, args...)
    ptr = Libc.malloc(size)
    man = Manual{T}(ptr)
    end_ptr = init(ptr + sizeof(T), man, args...)
    @assert end_ptr - ptr == size
    man
end

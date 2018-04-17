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

"""
    malloc(::Type{T}, args...)::Manual{T} where T

Allocate and initialize a new `Manual{T}`.
"""
function malloc(::Type{T}, args...)::Manual{T} where T
    ptr = Libc.malloc(alloc_size(T, args...))
    man = Manual{T}(ptr)
    init(man, args...)
    man
end

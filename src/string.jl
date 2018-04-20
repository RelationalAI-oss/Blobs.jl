"A string whose data is stored in a Blob."
struct BlobString <: AbstractString
    data::Blob{UInt8}
    len::Int64 # in bytes
end

Base.pointer(blob::BlobString) = pointer(blob, 1)
function Base.pointer(blob::BlobString, i::Integer)
    # TODO(jamii) would prefer to boundscheck on load, but this will do for now
    getindex(blob.data + (blob.len - 1))
    pointer(blob.data + (i-1))
end

function Base.unsafe_copy!(blob::BlobString, string::Union{BlobString, String})
    @assert blob.len >= sizeof(string)
    unsafe_copy!(pointer(blob), pointer(string), sizeof(string))
end

function Base.String(blob::BlobString)
    unsafe_string(pointer(blob), blob.len)
end

# string interface - this is largely copied from Base

Base.sizeof(s::BlobString) = s.len

if VERSION >= v"0.7.0-DEV"
    include("string7.jl")
else
    include("string6.jl")
end

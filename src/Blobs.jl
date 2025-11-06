module Blobs

using MacroTools
using Preferences: @load_preference

const BOUNDSCHECK_ON_DEREF_ENABLED::Bool = @load_preference("BLOBS_BOUNDSCHECK_ON_DEREF_ENABLED", false)

macro splice(iterator, body)
  @assert iterator.head == :call
  @assert iterator.args[1] == :in
  Expr(:..., :(($(esc(body)) for $(esc(iterator.args[2])) in $(esc(iterator.args[3])))))
end

include("blob.jl")
include("vector.jl")
include("bit_vector.jl")
include("string.jl")
include("layout.jl")

export Blob, BlobVector, BlobBitVector, BlobString, @v, @a

end

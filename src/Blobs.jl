module Blobs

using MacroTools

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

export Blob, BlobVector, BlobBitVector, BlobString, @v

end

module ManualMemory

macro splice(iterator, body)
  @assert iterator.head == :call
  @assert iterator.args[1] == :in
  Expr(:..., :(($(esc(body)) for $(esc(iterator.args[2])) in $(esc(iterator.args[3])))))
end

include("manuals.jl")
include("manual_vectors.jl")
include("manual_bit_vectors.jl")
include("manual_strings.jl")
include("manual_alloc.jl")

export Manual, ManualVector, ManualBitVector, ManualString, @a, @v

end

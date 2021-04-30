using Clang
using OpenEXR_jll

const OPENEXR_INCLUDE = joinpath(OpenEXR_jll.artifact_dir, "include", "OpenEXR") |> normpath
const OPENEXR_HEADERS = [joinpath(OPENEXR_INCLUDE, "ImfCRgbaFile.h")]

# create a work context
ctx = DefaultContext()

# parse headers
parse_headers!(ctx, OPENEXR_HEADERS,
               args=["-I", joinpath(OPENEXR_INCLUDE, "..")],
               includes=vcat(OPENEXR_INCLUDE, CLANG_INCLUDE),
               )

# settings
ctx.libname = "libOpenEXR"
ctx.options["is_function_strictly_typed"] = false
ctx.options["is_struct_mutable"] = false

# write output
api_file = joinpath(@__DIR__, "..", "src", "OpenEXR_api.jl")
api_stream = open(api_file, "w")

for trans_unit in ctx.trans_units
    root_cursor = getcursor(trans_unit)
    push!(ctx.cursor_stack, root_cursor)
    header = spelling(root_cursor)
    @info "wrapping header: $header ..."
    # loop over all of the child cursors and wrap them, if appropriate.
    ctx.children = children(root_cursor)
    for (i, child) in enumerate(ctx.children)
        child_name = name(child)
        child_header = filename(child)
        ctx.children_index = i
        # choose which cursor to wrap
        startswith(child_name, "__") && continue  # skip compiler definitions
        child_name in keys(ctx.common_buffer) && continue  # already wrapped
        child_header != header && continue  # skip if cursor filename is not in the headers to be wrapped

        wrap!(ctx, child)
    end
    @info "writing $(api_file)"
    println(api_stream, "# Julia wrapper for header: $(basename(header))")
    println(api_stream, "# Automatically generated using Clang.jl\n")
    print_buffer(api_stream, ctx.api_buffer)
    empty!(ctx.api_buffer)  # clean up api_buffer for the next header
end
close(api_stream)

# Remove definition of ImfHalf. We will define it as Float16 instead of UInt16.
pop!(ctx.common_buffer, :ImfHalf)

# Remove definition of ImfRgba. We will define it as RGBA{ImfHalf}.
pop!(ctx.common_buffer, :ImfRgba)

# Remove definition of IMF_WRITE_RGBA. It isn't correct.
pop!(ctx.common_buffer, :IMF_WRITE_RGBA)

# Write "common" definitions: types, typealiases, etc.
common_file = joinpath(@__DIR__, "..", "src", "OpenEXR_common.jl")
open(common_file, "w") do f
    println(f, "# Automatically generated using Clang.jl\n")
    print_buffer(f, dump_to_buffer(ctx.common_buffer))
end

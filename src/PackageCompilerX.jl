module PackageCompilerX

using Clang_jll
using Libdl

function test_clang()
    clang() do cc
        file = joinpath(@__DIR__, "..", "hello.cpp")
        run(`$cc $file -fuse-ld=lld`)
    end
end

function run_precompilation(precompilefile::String, project=Base.active_project)
    tmp = tempname()
    cmd = `$(Base.julia_cmd()) --project=$(repr(project)) --startup-file=no --trace-compile=$tmp $precompilefile`
    run(cmd)
    return readlines(tmp)
end


#=
function create_object(package::Symbol, project=Base.active_project(); precompilefile="precompile.jl")
    # Check that packages are available in project
    #precompile_statements = run_precompilation(precompilefile)
    tmp = tempname()
    julia_code = """Base.__init__(); using $package; include("hello.jl")"""
    #=
    julia_code *= """\n\n
    @eval Module() begin
        for (_pkgid, _mod) in Base.loaded_modules
            if !(_pkgid.name in ("Main", "Core", "Base"))
                @eval const $(Symbol(_mod)) = $_mod)
            end
        end
        include_time = statement in sort(collect(statements))
            # println(statement)
            try
                Base.include_string(PrecompileStagingArea, statement)
                n_succeeded += 1
            catch
                # See #28808
                # @error "Failed to precompile $statement"
            end
        end


    end
    """
    =#

    cmd = `$(Base.julia_cmd()) --color=yes --project=$project --output-o=sys.o --startup-file=no  -e $julia_code`
    @debug "Creating object file using $cmd"
    run(cmd)
end

function create_shared_library(input_object::String, output_library::String)
    julia_libdir = dirname(Libdl.dlpath("libjulia"))

    # TODO: Is --whole-archive, -all_load needed?
    # TODO: Check stack smash protection?
    # Prevent compiler from stripping all symbols from the shared lib.
    if Sys.isapple()
        o_file = `-Wl,-all_load $input_object`
    else
        o_file = `-Wl,--whole-archive $input_object -Wl,--no-whole-archive`
    end

    cmd = `$(SYSTEM_COMPILER) -shared -L$(julia_libdir) -o $output_library $o_file -ljulia`
    @debug "Creating  library using $cmd"
    run(cmd)
end
=#

end # module

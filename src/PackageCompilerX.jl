module PackageCompilerX

using Clang_jll
using Libdl

function test_clang()
    clang() do cc
        file = joinpath(@__DIR__, "..", "hello.cpp")
        run(`$cc -v $file -fuse-ld=lld`)
    end
end

function run_precompilation(precompilefile::String, project=Base.active_project)
    tmp = tempname()
    cmd = `$(Base.julia_cmd()) --project=$(repr(project)) --startup-file=no --trace-compile=$tmp $precompilefile`
    run(cmd)
    return readlines(tmp)
end

function create_object(package::Symbol, project=Base.active_project(); precompilefile="precompile.jl")
    # Check that packages are available in project
    #precompile_statements = run_precompilation(precompilefile)
    #=
    tmp = tempname()
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

    julia_code = """Base.__init__(); using $package"""
    cmd = `$(Base.julia_cmd()) --color=yes --project=$project --output-o=sys.o --startup-file=no  -e $julia_code`
    run(cmd)
end

function create_shared_library(input_object::String, output_library::String)
    julia_libdir = dirname(Libdl.dlpath("libjulia"))

    # Prevent compiler from stripping all symbols from the shared lib.
    if Sys.isapple()
        o_file = `-Wl,-all_load $input_object`
    else
        o_file = `-Wl,--whole-archive $input_object -Wl,--no-whole-archive`
    end
    
    clang() do cc
        run(`$cc -v -shared -L$(julia_libdir) -o $output_library $o_file -ljulia -fuse-ld=lld`)
    end
end


#=
function create_executable()
    clang() do cc
        run(`$cc -DJULIAC_PROGRAM_LIBNAME=  -o  embedding_wrapper.c sys.so 
    end

end
=#

end # module

module PackageCompilerX

const depsfile = joinpath(@__DIR__, "..", "deps", "deps.jl")
# defines SYSTEM_COMPILER

if isfile(depsfile)
    include(depsfile)
    try
        success(`$SYSTEM_COMPILER -v`)
    catch
        error("GCC wasn't found. Please make sure that gcc is on the path and run Pkg.build(\"PackageCompiler\")")
    end
else
    error("Package wasn't built correctly. Please run Pkg.build(\"PackageCompiler\")")
end

function running_julia_sysimg_path()
    return unsafe_string(Base.JLOptions().image_file)
end

function create_static_library(package::Symbol, project=Base.active_project())
    # Check that packages are available in project
    opts = Base.JLOptions()
    julia_code = "Base.__init__(); using $package"

    cmd = `$(Base.julia_cmd()) --project=$(repr(project)) --output-o=sys.a --startup-file=no  -e $julia_code`
    @show cmd
end

function create_shared_library()
    
    # Prevent compiler from stripping all symbols from the shared lib.
    if Sys.isapple()
        o_file = `-Wl,-all_load $o_file`
    else
        o_file = `-Wl,--whole-archive $o_file -Wl,--no-whole-archive`
    end
end

end # module

module PackageCompilerX

using Base: active_project
using Libdl: Libdl
using Pkg: Pkg

if isdefined(Pkg, :Artifacts)
    using Pkg.Artifacts
    const SUPPORTS_ARTIFACTS = true
else
    const SUPPORTS_ARTIFACTS = false
end

include("juliaconfig.jl")

const CC = (Sys.iswindows() ? `x86_64-w64-mingw32-gcc` : `gcc`)

function get_julia_cmd()
    julia_path = joinpath(Sys.BINDIR, Base.julia_exename())
    image_file = unsafe_string(Base.JLOptions().image_file)
    cmd = `$julia_path -J$image_file --color=yes --startup-file=no -Cnative`
end

# Returns a vector of precompile statemenets
function run_precompilation_script(project::String, precompile_file::String)
    tracefile = tempname()
    julia_code = """Base.__init__(); include($(repr(precompile_file)))"""
    run(`$(get_julia_cmd()) --project=$project --trace-compile=$tracefile -e $julia_code`)
    return tracefile
end

function create_object_file(object_file::String, packages::Union{Symbol, Vector{Symbol}};
                            project::String=active_project(),
                            precompile_execution_file::Union{String, Nothing}=nothing,
                            precompile_statements_file::Union{String, Nothing}=nothing)
    # include all packages into the sysimage
    packages = vcat(packages)
    julia_code = """
        if !isdefined(Base, :uv_eventloop)
            Base.reinit_stdio()
        end
        Base.__init__(); 
        """
    for package in packages
        julia_code *= "using $package\n"
    end
    
    # handle precompilation
    if precompile_execution_file !== nothing || precompile_statements_file !== nothing
        precompile_statements = ""
        if precompile_execution_file !== nothing
            @info "running precompilation execution script..."
            tracefile = run_precompilation_script(project, precompile_execution_file)
            precompile_statements *= "append!(precompile_statements, readlines($(repr(tracefile))))\n"
        end
        if precompile_statements_file != nothing
            precompile_statements *= "append!(precompile_statements, readlines($(repr(precompile_statements_file))))\n"
        end

        precompile_code = """
            # This @eval prevents symbols from being put into Main
            @eval Module() begin
                PrecompileStagingArea = Module()
                for (_pkgid, _mod) in Base.loaded_modules
                    if !(_pkgid.name in ("Main", "Core", "Base"))
                        eval(PrecompileStagingArea, :(const \$(Symbol(_mod)) = \$_mod))
                    end
                end
                precompile_statements = String[]
                $precompile_statements
                for statement in sort(precompile_statements)
                    # println(statement)
                    try
                        Base.include_string(PrecompileStagingArea, statement)
                    catch
                        # See julia issue #28808
                        @error "failed to execute \$statement"
                    end
                end
            end # module
            """
        julia_code *= precompile_code
    end

    # finally, make julia output the resulting object file
    @debug "creating object file at $object_file"
    @info "PackageCompilerX: creating object file, this might take a while..."
    run(`$(get_julia_cmd()) --project=$project --output-o=$(object_file) -e $julia_code`)
end

default_sysimage_path() = joinpath(julia_private_libdir(), "sys." * Libdl.dlext)
backup_sysimage_path() = default_sysimage_path() * ".backup"

function create_sysimage(packages::Union{Symbol, Vector{Symbol}}=Symbol[];
                         sysimage_path::Union{String,Nothing}=nothing,
                         project::String=active_project(),
                         precompile_execution_file::Union{String, Nothing}=nothing,
                         precompile_statements_file::Union{String, Nothing}=nothing,
                         replace_default_sysimage::Bool=false)
    if sysimage_path === nothing && replace_default_sysimage == false
        error("`sysimage_path` cannot be `nothing` if `replace_default_sysimage` is `false`")
    end
    if sysimage_path === nothing
        sysimage_path = string(tempname(), ".", Libdl.dlext)
    end

    object_file = tempname() * ".o"
    create_object_file(object_file, packages; project=project, precompile_execution_file=precompile_execution_file,
                       precompile_statements_file=precompile_statements_file)
    create_sysimage_from_object_file(object_file, sysimage_path)
    if replace_default_sysimage
        if !isfile(backup_sysimage_path())
            cp(default_sysimage_path(), backup_sysimage_path())
            @debug "making a backup of sysimage"
        end
        @info "PackageCompilerX: default sysimage replaced, restart Julia for the new sysimage to be in effect"
        cp(sysimage_path, default_sysimage_path(); force=true)
    end
    # TODO: Remove object file
end

function create_sysimage_from_object_file(input_object::String, sysimage_path::String)
    julia_libdir = dirname(Libdl.dlpath("libjulia"))

    # Prevent compiler from stripping all symbols from the shared lib.
    # TODO: On clang on windows this is called something else
    if Sys.isapple()
        o_file = `-Wl,-all_load $input_object`
    else
        o_file = `-Wl,--whole-archive $input_object -Wl,--no-whole-archive`
    end
    extra = Sys.iswindows() ? `-Wl,--export-all-symbols` : ``
    run(`$CC -v -shared -L$(julia_libdir) -o $sysimage_path $o_file -ljulia $extra`)
    return nothing
end

function restore_default_sysimage()
    if !isfile(backup_sysimage_path())
        error("did not find a backup sysimage")
    end
    cp(backup_sysimage_path(), default_sysimage_path(); force=true)
    rm(backup_sysimage_path())
    @info "PackageCompilerX: default sysimage restored, restart Julia for the new sysimage to be in effect"
    return nothing
end

# This requires that the sysimage have been built so that there is a ccallable `julia_main`
# in Main.
function create_executable_from_sysimage(;sysimage_path::String,
                                          executable_path::String,
                                          relative_lib_dir::String=".")
    flags = join((cflags(), ldflags(), ldlibs()), " ")
    flags = Base.shell_split(flags)
    wrapper = joinpath(@__DIR__, "embedding_wrapper.c")
     if Sys.iswindows()
        rpath = ``
    elseif Sys.isapple()
        rpath = `-Wl,-rpath,@executable_path/$relative_lib_dir`
    else
        rpath = `-Wl,-rpath,\$ORIGIN/$relative_lib_dir`
    end
    extra = Sys.iswindows() ? `-Wl,--export-all-symbols` : ``
    cmd = `$CC -v -DJULIAC_PROGRAM_LIBNAME=$(repr(joinpath(relative_lib_dir, sysimage_path))) -o $(executable_path) $(wrapper) $(sysimage_path) -O2 $rpath $flags $extra`
    @debug "running $cmd"
    run(cmd)
    return nothing
end

function create_app(package_dir::String;
                    precompile_execution_file::Union{String,Nothing}=nothing,
                    precompile_statements_file::Union{String,Nothing}=nothing,
                    # sysimage_path::Union{String,Nothing}=nothing, # optional sysimage
                    bundle=true,
                    force=false)
    project_toml_path = abspath(Pkg.Types.projectfile_path(package_dir; strict=true))
    manifest_toml_path = abspath(Pkg.Types.manifestfile_path(package_dir; strict=true))
    project_toml = Pkg.TOML.parsefile(project_toml_path)
    project_path = abspath(package_dir)
    app_name = get(() -> error("expected package to have a name entry"), project_toml, "name")
    sysimage_file = app_name * "." * Libdl.dlext
    app_dir = joinpath(package_dir, app_name)
    # Should we clear out the previous installation??
    
    #=
    if isdir(app_dir)
        if !force
            error("directory $(repr(app_dir)) already exists, use `force=true` to overwrite")
        end
        rm(app_dir; force=true, recursive=true)
    end
    =#
   
    mkpath(app_dir)
    #@Quality: Maybe avoid these cds?
    #@Correctness: Copy project files
    #@Correctness: Copy artifacts
    #
    if bundle
        bundle_project(project_toml_path, manifest_toml_path, app_dir)
        bundle_julia_libraries(app_dir)
        if SUPPORTS_ARTIFACTS
            # bundle_artifacts(app_dir)
        end
    end
    cd(app_dir) do
        if bundle
            sysimage_dir = joinpath("lib")
        else
            sysimage_dir = "."
        end
        mkpath("project")
        bundle_artifacts(".")
        @show project_toml_path

        mkpath("lib")

        create_sysimage(Symbol(app_name); sysimage_path=sysimage_file, project=project_path)
        mkpath("bin")
        create_executable_from_sysimage(; sysimage_path=sysimage_file, executable_path=joinpath("bin", app_name), relative_lib_dir="../lib/julia")
        cp(sysimage_file, joinpath("lib", "julia", sysimage_file))
    end
    #end
end

function bundle_project(project_toml_path, manifest_toml_path, app_dir)
    cp(project_toml_path, joinpath(app_dir, "project", "Project.toml"); force=true)
    cp(manifest_toml_path, joinpath(app_dir, "project", "Manifest.toml"); force=true)
end

function bundle_julia_libraries(app_dir)
    if Sys.isunix()
        app_libdir = joinpath(app_dir, "lib")
        cp(julia_libdir(), app_libdir; force=true)
        rm(joinpath(app_dir, "lib", "julia", "sys.so"); force=true)
        rm(joinpath(app_dir, "lib", "julia", "sys.so.backup"); force=true)
    end
end

function bundle_artifacts(app_dir)
    artifact_toml_path = find_artifacts_toml(app_dir)
    if artifact_toml_path == nothing
        return
    end
    artifact_dict = Pkg.Artifacts.load_artifacts_toml(artifact_toml_path)

    artifact_paths = String[]
    @info "installing and bundling artifacts..."
    for name in keys(artifact_dict)
        @info "    $name"
        push!(artifact_paths, ensure_artifact_installed(name, artifact_toml_path))
    end
    app_artifact_dir = joinpath(app_dir, "artifacts")
    mkpath(app_artifact_dir)
    for artifact_path in artifact_paths
        cp(artifact_path, joinpath(app_artifact_dir, basename(artifact_path)); force=true)
    end
    @show artifact_paths
end

# For bundled apps we replicate the file structure adopted by Julia itself.
#
# On Windows we copy all libraries except the sysimage to bin
# #
function copy_julia_libs(builddir, verbose)
    # TODO: these flags should probably be emitted also by `julia-config.jl` and `compiler_flags.jl`
    shlibdir = Sys.iswindows() ? Sys.BINDIR : joinpath(Sys.BINDIR, Base.LIBDIR)
    private_shlibdir = joinpath(Sys.BINDIR, Base.PRIVATE_LIBDIR)
    libfiles = String[]
    dlext = "." * Libdl.dlext
    for dir in (shlibdir, private_shlibdir)
        if Sys.iswindows() || Sys.isapple()
            append!(libfiles, joinpath.(dir, filter(x -> endswith(x, dlext) && !startswith(x, "sys"), readdir(dir))))
        else
            append!(libfiles, joinpath.(dir, filter(x -> occursin(r"^lib.+\.so(?:\.\d+)*$", x), readdir(dir))))
        end
    end
    filter!(v -> !occursin(r"debug", v), libfiles)
    copy_files_array(libfiles, builddir, verbose, "Copy Julia libraries to build directory:")
end

end # module

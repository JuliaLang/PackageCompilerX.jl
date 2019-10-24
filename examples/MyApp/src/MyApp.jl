module MyApp

using Example
using Pkg.Artifacts
import Pkg

greet() = print("Hello World!")




Base.@ccallable function julia_main(ARGS::Vector{String})::Cint
    try
        @show @macroexpand artifact"socrates"
        println("hello, world")
        artifact_path = artifact"socrates"
        @show artifact_path
        socrates = joinpath(artifact_path, "bin", "socrates")
        run(`$socrates`)
        println()
        #"@show artifact_path
        #@show readdir(artifact_path)
        
        @show unsafe_string(Base.JLOptions().image_file)
        @show DEPOT_PATH
        @show pwd()
        @show LOAD_PATH
        @show Base.active_project()
        @show Example.domath(5)
        @show sin(0.0)
        @show Sys.BINDIR
        error()
        return 0
    catch e
        Base.showerror(stdout, catch_backtrace())
        return -1
    end
end

end # module

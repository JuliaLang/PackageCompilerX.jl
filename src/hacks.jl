# This function contains various hacks that are needed due to
# bugs in Julia or packages
function ugly_workarounds(packages::Vector{Symbol})
    hack_code = ""

    # Workaround https://github.com/JuliaLang/julia/issues/34061
    # for Plots.jl
    if :Plots in packages
        hack_code *= """
        @eval Module() begin
            gr_id = Base.PkgId(Base.UUID("28b8d3ca-fb5f-59d9-8090-bfdbd6d07a71"), "GR")
            GR = get(Base.loaded_modules, gr_id, nothing)
            if GR !== nothing
                GR.__init__()
            end
        end
        """
        @show hack_code
    end


    return hack_code
end

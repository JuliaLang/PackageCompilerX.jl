# This function contains various hacks that are needed due to
# bugs in Julia or packages
function ugly_workarounds()
    hack_code = ""

    # Workaround https://github.com/JuliaLang/julia/issues/34061
    # for Plots.jl
    hack_code *= """
    @eval Module() begin
        plots_id = Base.PkgId(Base.UUID("91a5bcdd-55d7-5caf-9e0b-520d859cae80"), "Plots")
        if haskey(Base.loaded_modules, plots_id)
            gr_id = Base.PkgId(Base.UUID("28b8d3ca-fb5f-59d9-8090-bfdbd6d07a71"), "GR")
            GR = get(Base.loaded_modules, gr_id, nothing)
            if GR !== nothing
                GR.__init__()
            end
        end
    end
    """
    @show hack_code


    return hack_code
end

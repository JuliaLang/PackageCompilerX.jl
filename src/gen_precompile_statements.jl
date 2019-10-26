using Pkg: Pkg
abstract type PrecompileSource end

struct RunTests <: PrecompileSource
    pkg::Symbol
end
struct RunUsing <: PrecompileSource
    pkg::Symbol
end
struct RunFile <: PrecompileSource
    path::String
end
struct RunCode <: PrecompileSource
    code::String
end
struct StatementFile <: PrecompileSource
    path::String
end

struct PrecompileStatements
    statements::Vector{String}
end

PrecompileStatements() = PrecompileStatements(String[])

function Base.merge!(o1::PrecompileStatements, o2::PrecompileStatements)
    Base.append!(o1.statements, o2.statements)
    o1
end


function populate_precompile_statement_file(tracefile::AbstractString, o::RunTests)
    Pkg.test(String[string(o.pkg)], julia_args=["--trace-compile=$tracefile"])
    tracefile
end

function populate_precompile_statement_file(tracefile::AbstractString, o::RunCode)
    cmd = `$(Base.julia_cmd()) --trace-compile=$tracefile -e "$(o.code)"`
    run(cmd)
    tracefile
end

function populate_precompile_statement_file(tracefile::AbstractString, o::RunUsing)
    @assert o.pkg != nothing
    cmd = `$(Base.julia_cmd()) --trace-compile=$tracefile -e "using $(o.pkg)"`
    run(cmd)
    tracefile
end

function populate_precompile_statement_file(tracefile::AbstractString, o::RunFile)
    @assert o.pkg != nothing
    cmd = `$(Base.julia_cmd()) --trace-compile=$tracefile $(o.path)`
    run(cmd)
    tracefile
end

function populate_precompile_statement_file(tracefile::AbstractString, o::StatementFile)
    cp(o.path, tracefile)
    tracefile
end

function generate_statements(o::PrecompileSource)
    mktemp() do path, io
        populate_precompile_statement_file(path, o)
        return load_precomiple_statements(path)
    end
end

function generate_statements(precompile_sources)
    mapreduce(generate_statements, merge!, precompile_sources, init=PrecompileStatements())
end

load_precompile_statements(path::AbstractString) = open(load_precompile_statements, path)
load_precompile_statements(io::IO) = PrecompileStatements(readlines(io))

function save(io::IO, o::PrecompileStatements)
    for s in o.statements
        println(io, s)
    end
end
function save(path::AbstractString, o::PrecompileStatements)
    open(path, "w") do io
        save(io, o)
    end
end

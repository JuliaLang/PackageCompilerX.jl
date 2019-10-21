using PackageCompilerX
using Test
using Libdl

@testset "PackageCompilerX.jl" begin
    PackageCompilerX.test_clang()
    # Write your own tests here.
    PackageCompilerX.create_object(:Example)
    sysimg = "sys." * Libdl.dlext
    PackageCompilerX.create_shared_library("sys.o", sysimg)
    run(`$(Base.julia_cmd()) -J $(sysimg) -e 'println(1337)'`)
end

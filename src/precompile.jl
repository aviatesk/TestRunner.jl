module Precompile

using ..TestRunner: TestRunner, runtest
using PrecompileTools

module PrecompileModule1 end
module PrecompileModule2 end
module PrecompileModule3 end
module PrecompileModule4 end
module PrecompileModule5 end

@setup_workload let
    @compile_workload redirect_stdout(devnull) do
        demo_file = pkgdir(TestRunner, "demo.jl")
        runtest(demo_file, ["basic tests"]; topmodule=PrecompileModule1); # Run "basic tests" including @test_broken
        runtest(demo_file, [:(@test process(s_) == n_)]; topmodule=PrecompileModule2) # Run tests that call the process function
        runtest(demo_file, [r".*tests"]; topmodule=PrecompileModule3)
        runtest(demo_file, ["inner tests 1"]; topmodule=PrecompileModule4); # Run a specific nested testset
        runtest(demo_file, [:(@test startswith(s_, prefix_))]; topmodule=PrecompileModule5); # Match expression patterns within nested testsets
    end
end

end # module Precompile

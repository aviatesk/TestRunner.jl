@warn """
TestRunner.jl has moved into JETLS.jl as the `TestRunner` subpackage, and \
https://github.com/aviatesk/TestRunner.jl is no longer updated. \
Reinstall the `testrunner` app from JETLS.jl to keep receiving updates:

    julia -e 'using Pkg; Pkg.Apps.add(; url="https://github.com/aviatesk/JETLS.jl", subdir="TestRunner", rev="release")'

If you use JETLS, its `jetls test` command also runs tests with the TestRunner bundled with JETLS:

    jetls test test/runtests.jl "my tests"

See https://github.com/aviatesk/TestRunner.jl#migration for details.
"""

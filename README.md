# TestRunner.jl

> [!important]
> TestRunner.jl has moved into [JETLS.jl](https://github.com/aviatesk/JETLS.jl)
> as the
> [`TestRunner` subpackage](https://github.com/aviatesk/JETLS.jl/tree/master/TestRunner),
> and this repository is no longer updated.
> See the
> [README of the subpackage](https://github.com/aviatesk/JETLS.jl/blob/master/TestRunner/README.md)
> for the documentation.

## Migration

### The `testrunner` app

Reinstall the `testrunner` app from JETLS.jl:

```bash
julia -e 'using Pkg; Pkg.Apps.add(; url="https://github.com/aviatesk/JETLS.jl", subdir="TestRunner", rev="release")'
```

This replaces the `testrunner` app installed from this repository, and the
command line interface stays the same.

### Running tests with JETLS

If you use [JETLS](https://github.com/aviatesk/JETLS.jl), its
[`jetls test`](https://aviatesk.github.io/JETLS.jl/release/testrunner/#testrunner/cli)
command also runs tests with the TestRunner bundled with JETLS, and takes the
same patterns and options as the `testrunner` app:

```bash
jetls test test/runtests.jl "my tests"
```

### TestRunner as a package

Add TestRunner from JETLS.jl instead:

```julia
using Pkg
Pkg.add(; url="https://github.com/aviatesk/JETLS.jl", subdir="TestRunner")
```

### The TestRunner integration of JETLS

The
[TestRunner integration of JETLS](https://aviatesk.github.io/JETLS.jl/release/testrunner/)
uses the TestRunner bundled with JETLS, so no action is needed for it.

## Existing installations

Installations from this repository keep working, but they no longer receive
updates. The `testrunner` app installed from the `release` branch shows a
migration notice when it is installed or updated, and when it runs without
`--json`.

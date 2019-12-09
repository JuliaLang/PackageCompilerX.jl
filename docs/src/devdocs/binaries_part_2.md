---
layout: post
title: Custom system images and apps in Julia -- The manual way -- Part 2
author: <a href="https://github.com/KristofferC">Kristoffer Carlsson</a>
---

This is part 2 in a series of blog posts related to creating custom sysimages
and executables (apps) that can be shipped to other machines in Julia. Part 1
focused on how to build a local system image to reduce package load times and
reduce latency when calling a function for the first time. This part (part 2)
targets how to build an executable based on the custom sysimage so that it can
be run without having to explicitly start a Julia session.  Part 3 (yet to be
written) details how to bundle that executable together with the Julia
libraries and other files needed so that the bundle can be sent to and run on a
different system where Julia might not be installed.  Most things that were
described in part 1 will be used here, so make sure to read that first!

## Interacting with Julia

The way to interact with Julia without using the Julia executable itself is by
calling into the Julia runtime library (`libjulia`) from a C program.  A quite
detail set of docs for how this is done can be found at the [embedding chapter
in the Julia manual][embedding-url] and it is recommended to read before
reading on.  Since this is "the manual way" we will not use the conveniences
shown in that section (e.g. the `julia-config.jl` script) but it is good to
know they exist.

A rough outline of the steps we will take to create an executable are:

- Create our Julia app with a `Base.@ccallable` entry-point which means the Julia
  function can be called from C.
- Create a custom sysimage to reduce latency (this is pretty much just doing
  part 1) and to hold the c-callable function from the first step.
- Write an embedding wrapper in C that loads our custom sysimage, does some
  initialization and calls the entry point in the script.

## Creating the app -- A toy application

To have something concrete to work with we will create a very simple
application.  In keeping with the spirit of CSV parsing from part 1, we will create
a small app that parses a list of CSV files given as arguments to the app and
prints the size of the parsed result. The code for the app (`MyApp.jl`) is shown below:

```jl
module MyApp

using CSV

Base.@ccallable function julia_main()::Cint
    try
        real_main()
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end
    return 0
end

function real_main()
    for file in ARGS
        if !isfile(file)
            error("could not find file $file")
        end
        df = CSV.read(file)
        println(file, ": ", size(df, 1), "x", size(df, 2))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    real_main()
end

end # module
```

The function `julia_main` has been annotated with `Base.@ccallable` which means
that a function with the unmangled name will appear in the sysimage. This
function is just a small wrapper function that calls out to `real_main` which
does the actual work.  All the code that is executed is put inside a try-catch
block since the error will otherwise happen in the C-code where the backtrace
is not very good

To facilitate testing, we [check if the file was directly executed][check-execute-url] and
in that case, run the main function.
We can test (and time) the script on the sample CSV file from part 1:

```
❯ time julia MyApp.jl FL_insurance_sample.csv
FL_insurance_sample.csv: 36634x18
julia MyApp.jl FL_insurance_sample.csv  12.51s user 0.38s system 104% cpu 12.385 total
``` 

## Create the sysimage

As in part 1, we do a "sample run" of our app to record what functions end up getting compiled.
Here, we simply run the app on the sample CSV file since that should give good "coverage":

```jl
julia --startup-file=no --trace-compile=app_precompile.jl MyApp.jl "FL_insurance_sample.csv"
```

The `create_sysimage.jl` script look similar to part 1 except we added an include of the app file
inside the anonymous module where the precompiliation statements are evaluated in:

```jl
Base.init_depot_path()
Base.init_load_path()

@eval Module() begin
    Base.include(@__MODULE__, "MyApp.jl")
    for (pkgid, mod) in Base.loaded_modules
        if !(pkgid.name in ("Main", "Core", "Base"))
            eval(@__MODULE__, :(const $(Symbol(mod)) = $mod))
        end
    end
    for statement in readlines("app_precompile.jl")
        try
            Base.include_string(@__MODULE__, statement)
        catch
            # See julia issue #28808
            Core.println("failed to compile statement: ", statement)
        end
    end
end # module

empty!(LOAD_PATH)
empty!(DEPOT_PATH)
```

The sysimage is then created as in part 1:

```
❯ julia --startup-file=no -J"/home/kc/julia/lib/julia/sys.so" --output-o sys.o custom_sysimage.jl

❯ gcc -shared -o sys.so -fPIC -Wl,--whole-archive sys.o -Wl,--no-whole-archive -L"/home/kc/julia/lib" -ljulia
```

### Windows-specific flags

For Windows we need to tell the linker to export all symbols via the flag `-Wl,--export-all-symbols`.
Otherwise, the linker will fail to find `julia_main` when we build the executable.

## Creating the executable

### Embedding code

The embedding script is the "driver" of the app. It initializes the julia
runtime, does some other initialization, calls into our `julia_main` and then
does some cleanup when it returns.  We can borrow a lot for this embedding
script from the embedding manual there are however some things we ne
ed to set up
"manually" that Julia usually does by itself when starting Julia.  This
includes assigning the `PROGRAM_FILE` variable as well as updating `Base.ARGS`
to contain the correct values. The script `MyApp.c` ends up looking like:

```c
// Standard headers
#include <string.h>
#include <stdint.h>

// Julia headers (for initialization and gc commands)
#include "uv.h"
#include "julia.h"

JULIA_DEFINE_FAST_TLS()

// Forward declare C prototype of the C entry point in our application
int julia_main();

int main(int argc, char *argv[])
{
    uv_setup_args(argc, argv);

    // initialization
    libsupport_init();

    // JULIAC_PROGRAM_LIBNAME defined on command-line for compilation
    jl_options.image_file = JULIAC_PROGRAM_LIBNAME;
    julia_init(JL_IMAGE_JULIA_HOME);

    // Initialize Core.ARGS with the full argv.
    jl_set_ARGS(argc, argv);

    // Set PROGRAM_FILE to argv[0].
    jl_set_global(jl_base_module,
        jl_symbol("PROGRAM_FILE"), (jl_value_t*)jl_cstr_to_string(argv[0]));

    // Set Base.ARGS to `String[ unsafe_string(argv[i]) for i = 1:argc ]`
    jl_array_t *ARGS = (jl_array_t*)jl_get_global(jl_base_module, jl_symbol("ARGS"));
    jl_array_grow_end(ARGS, argc - 1);
    for (int i = 1; i < argc; i++) {
        jl_value_t *s = (jl_value_t*)jl_cstr_to_string(argv[i]);
        jl_arrayset(ARGS, s, i - 1);
    }

    // call the work function, and get back a value
    int ret = julia_main();

    // Cleanup and gracefully exit
    jl_atexit_hook(ret);
    return ret;
}
``` 

## Building the executable

We now have all the pieces needed to build the executable; a sysimage and a driver script.
It is compiled as:

```
❯ gcc -DJULIAC_PROGRAM_LIBNAME=\"sys.so\" -o MyApp MyApp.c sys.so -O2 -fPIE \
    -I'/home/kc/julia/include/julia' \
    -L'/home/kc/julia/lib' \
    -ljulia \
    -Wl,-rpath,'/home/kc/julia/lib:$ORIGIN'
```

where we have added an `rpath` entry into the executable so that the julia
library can be found at runtime as well as the `sys.so` library ($ORIGIN means
to look in the same folder as the binary for shared libraries).

```
❯ time ./MyApp FL_insurance_sample.csv
FL_insurance_sample.csv: 36634x18
./MyApp FL_insurance_sample.csv  0.19s user 0.09s system 242% cpu 0.115 total

❯ ./MyApp non_existing.csv
ERROR: could not find file non_existing.csv
Stacktrace:
 [1] error(::String) at ./error.jl:33
 [2] real_main() at /home/kc/MyApp/MyApp.jl:21
 [3] julia_main() at /home/kc/MyApp/MyApp.jl:7 
```

### macOS considerations

On macOS, instead of `$ORIGIN` for the `rpath`, use `@executable_path`.


### Windows considerations

On Windows, it is recommended to increase the size of the stack from the
default 1 MB to 8MB which can be done by passing the `-Wl,--stack,8388608`
flag.  Windows doesn't have (at least in an as simple way as Linux and macOS)
the concept of `rpath`.  The goto solution is to either set the `PATH`
environment variable to the Julia `bin` folder or alternatively copy paste all
the libraries in the Julia `bin` folder so they sit next to the executable.


# Summary

This blogpost took us from knowing how to create a sysimage to how to create an
executable calling into the julia runtime and starting up an "app" for us.
Note that the binary produced here is not at all relocatable (trying to send it
to a different machine will not work). In the next part (part 3) of this blog
we will look at what modifications we need to do to the embedding script, what
files we need to bundle, and what requirements packages need to adhere to in
order to be relocatable

[embedding-url]: https://docs.julialang.org/en/v1/manual/embedding/
[check-execute-url]: https://docs.julialang.org/en/v1/manual/faq/#How-do-I-check-if-the-current-file-is-being-run-as-the-main-script?-1



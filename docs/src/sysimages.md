# Sysimages

## What is a sysimage

A sysimage is a file which, in a loose sense, contains a Julia session.  A
"Juia session" include things like loaded packages, global variables, inferred
and compiled code, etc.  By starting julia with a sysimage, the stored Julia
session in the sysimage is quickly deserialized and . This is faster than
having to reload and recompile the code from scratch.

Julia itself ships with a sysimage that is used by default when Juia is
started. It contains the julia compiler itself, the standard libraries and also
precompile code (precompile statements) that has been put there to reduce the
time required to do common operations, like working in the REPL.

Sometimes, it is desireable to create a custom sysimage with custom precompile
statements. This is the case if one have some dependencies that take a
significant time to load or where the compilation time for the first call is
uncomfortably long. The document here is intended to document how to use
PackageCompilerX to create such sysimages.

### Drawbacks to custom sysimages

It should be clearly stated that there are some drawbacks to using a custom
sysimage, thereby sidestepping the standard Julia package precompilation
system.  The biggest drawback is that packages that are compiled into a
sysimage are "locked" to the version they where at when the sysimage was created.
This means that no matter what package version you have installed in your current
project, the one in the sysimage will take precedence. This can lead to bugs
where you might
Another effect is that you cannot really develop packages that are in the sysimage.

Putting packages in the sysimage should only be done if they are a 
and they are not frequently updated.

## Creating a sysimage using PackageCompilerX

PackageCompilerX provides the function [`create_sysimage`](@ref) to create a sysimage.
It takes as the first argument a package or a list of packages that should be embedded
in the resulting sysimage. After the sysimage is created, loading Julia with `-Jpath/to/sysimage`
will 



Alterntively, instead of giving a path to where the new sysimage should appear, one
can chose to replace the default sysimage

```
create_sysimage([:Debugger, :OhMyREPL]; replace_default=true)
````

If this is the first time `create_sysimage` is called with `replace_default`, a backup 
of the default sysimage is created. The default sysimage can then be restored with
[`restore_default_sysimage()`](@ref).

### Precompilation




### Incremental vs non-incremental sysimages

By default, when creating a sysimage with PackageCompilerX, the sysimage is created in "incremental"-mode.
This means that the 
This has the benefit that 



THat means if one uses the package manager to eg. update the package, the

Also, the version of the pacage inside the sysimage will be loaded no matter
what project that is used

Nevertheless, there are cases where a custom sysimage can impove the exepience.



## Adding precompilation statements to the sysimage

### Using a script


### Using a manually generated list of precompile statements

Starting julia with `--trace-compile=file.jl` will emit precompilation statements to `file.jl` 



- link to the example with OMR

- using snoopcompile




# Thoughts on the Zig Programming Language

Nick and I had the chance to have a zig community member hop on a zoom call,
answer our questions, and look at some code.  It was great!  Incredibly helpful
for jumpstarting our understanding of both where the language is and where it
is going next.

# Why Prototype in Zig

The project was for OpenTimelineIO (http://opentimeline.io), which is a library
that ships C++ and Python API -- neither of which is zig.  So why use Zig to
prototype?

- We wanted a language with strict types and structs, because the specific
  project had to do with changing the way the structs were designed
- by using a language where the original implementation is not available, we
  are more free to change details of the existing implementation

# How Ready Is the Language for Production?

The zig community member was quick to discourage us from using it for
production.  In general, it feels like most of the syntax and features they
want in the language are there, but there are still some gaps to be filled in.
They are also filling in their standard library.  In our prototyping, we didn't
run into anything that we wanted that was missing, but we were doing more of an
algorithm test than a system test.

Compiler wise, the main compiler is an llvm direct-to-machine code (IE no C
intermediate as many of these newer languages are doing) pipeline.  They are
additionally working on a "Stage 2" compiler which removes the LLVM dependency,
with intent to use it for non-optimized builds and for building into embedded
system environments.  The LLVM backend gives them cool cross compiler
functionality, and they're developing WASM and SPIR-V backends, in addition to
the typical machine code backends (x86-64, etc.).

The state goal is that the stage two compiler will be part of the first official
release. The first release target date is Novemeber 2021.

# Language Philosophy and Design

Zig has a "zen" it will print out if you run `zig zen`:
```
* Communicate intent precisely.
* Edge cases matter.
* Favor reading code over writing code.
* Only one obvious way to do things.
* Runtime crashes are better than bugs.
* Compile errors are better than runtime crashes.
 * Incremental improvements.
 * Avoid local maximums.
 * Reduce the amount one must remember.
 * Focus on code rather than style.
 * Resource allocation may fail; resource deallocation must succeed.
 * Memory is a resource.
 * Together we serve the users.
 ```
This feels like a pretty good representation for how the language feels in
pracftice to use.

# Features

## "No hidden control flow"

The meta observation is that while many langauges post-c aimed to "automate
boilerplate" (see: RAII) or remove it, zig instead aims to make the boilerplate
ergonomic, but not hide it from you.

In practice, this worked surprisingly well for me.  A good example is the `try`
command.

### Example: `try` statement

Zig doesn't support exceptions, rather function return types can be decorated
with a `!` to indicate that it can return either an error union or the
specified return type.  For example, a function with the return type of `!i32`
can return either an `int32_t` or an error union.  Functions that have a return
type with a `!` must be called either with a `catch` statement or a `try`.  A `catch`
statement has the form:
```zig
pub fn outer() !i32 {
    var foo = my_function() catch |err| return err;
    return foo;
}
```
This calls the function, and in the event of an error union return, will return
the error instead of foo.  The `try` statement is syntactic sugar for this:
```zig
var foo = try my_function();
```
The result is that your functions can end up with a lot of try statements:

```zig
const output_domain = try otio.build_24fps_192khz_output_domain();
try otio.print_structure(output_domain, 0);

const frames_to_render = audio_frames_to_render(tl, output_domain);
```

...But each `try` statement indicates a line which could return early.  I found
that made it really clear where an error _could_ come for.  This was
surprisingly readable and helped understanding what the language was doing.  In
this example, both `build_24fps_192khz_output_domain` and `print_structure` could
throw an error, but `audio_frames_to_render` cannot.

### Example: "defer" statement

Another example of this is the `defer` statement.  This statement will trigger
an experssion to run when the scope is closed, which can happen because of
hitting a `}`, `return` statement or having a `try` block trigger an early
return.

Rather than implement a language-wide "RAII" feature set with destructors like
C++, zig requires that you call the deallocator function if necessary, with the
typical pattern to call a dealloc() or deinit() function with a defer after
building the object:

```zig
var my_heap_obj = SomeType.init();
defer my_heap_obj.dealloc();
```

Again, this seemed at first like extra overhead but in practice makes code
_very_ clear about when exactly deallocations occur.  It also empowers you more
easily to make decisions about when memory is deallocated -- when using arena
allocators for example, you may want to deallocate the entire arena at once
rather than individual fields of a data structure.

...And mixed with the try blocks its very clear where a deallocation might
occur due to an early exit:

```zig
var my_heap_obj = SomeType.init();
defer my_heap_obj.dealloc();

const output_domain = try otio.build_24fps_192khz_output_domain();
try otio.print_structure(output_domain, 0);

const frames_to_render = audio_frames_to_render(tl, output_domain);
```

Here, my_heap_obj might be deallocated after `build_24fps_192khz_output_domain`
or `print_structure` but not after `audio_frames_to_render` (unless that was
also the end of the block)

## Light Syntax

The result of that design pattern is that unlike a language like C++, which has
a lot of special purpose syntax for different things, the language is pretty
minimal.  Instead of needing to learn a lot of syntax to do things, its about
learning the patterns in the language to solve problems like polymorphism.

There is little additional punctuation-syntax compared to other recent languages.
Some slightly odd details are using a pair of pipes to indicate the target of a
for loop, at signs here and there, and arrows in switch statements.

```zig
switch (@TypeOf(obj)) {
        // to the left of the arrow is the match, to the right is a block label
        Timeline => blk: {
            try print_structure(obj.tracks, offset + 2);
            break :blk;
        },
        // if not needed, the block label can be omitted (it can be omitted in
        // the above example as well)
        Sequence => {
            for (obj.children.items) |child| {
                try print_structure(child.clip, offset + 2);
            }
        },
        // switch statements are required to be exhaustive
        else => {}
```

There's a detail also about declaring tagged unions (unions with a flag that
indicates which union member is active) that seems slightly busy/in-the-know:

```zig
// tagged union
pub const OTIOMetadata = union (enum) {
    float: f64,
    int: i64,
    string: []const u8,
    boolean: bool,
    nil: void,
    dict: OTIOMetadataDict,
    list: std.ArrayList(OTIOMetadata),
};

// non-tagged union
pub const Example = union {
    f64,
    i64
};
```

## Union Types

The unions mentioned above are a suprisingly effective way of saying "this
family of types" for an interface.  The tagged enums have the additional 
advantage of being able to compare directly to the tagged types.

## "Test" Scopes

Zig has a nice integrated test harness. You can declare a test scope at the
scope of a file like:

```zig
test "add test" {
    const a = 3;
    const b = 6;

    expectEquals(a, b);
}
```

Code in a test scope is ignored unless the compiler is invoked with `zig test`,
in which case all the test scopes are compiled and executed.  That lets you 
nicely interleave your tests with your code however you'd like:

```zig
pub const CyclicalCoordinate = struct {
    value : i32,
    rate: i32
};
pub fn add_coord(
    fst: CyclicalCoordinate,
    snd: CyclicalCoordinate
) CyclicalCoordinate 
{
    return CyclicalCoordinate { 
        value = fst.value + fst.rate * snd.value / snd.rate,
        rate = fst.rate
    };
}
test "add test" {
    const a = CyclicalCoordinate { value=1, rate=24 };
    const b = CyclicalCoordinate { value=3, rate=24 };

    expectEquals(add_coord(a, b).value, 4);
}
```

One subtle feature with the test scopes is that you can use it to test out 
different implementations of the same idea very compactly in a single file.

```zig
test "int test" {
    // note that you cannot use the `pub` keyword here
    const CyclicalCoordinate = struct {
        value : i32,
        rate: i32
    };
    // test int...
}

test "float test" {
    const CyclicalCoordinate = struct {
        value : f32,
        rate: f32
    };

    // test float...
}
```

## Integrated Build/Package System

Especially based on our various attempts of getting OpenTimelineIO to sit
nicely in the python ecosystem zig is a breath of fresh air.  Nice things:

1. `zig init-exe` and `zig init-lib` to set a project up with a template
2. to add a submodule as a dependency, in your build.zig:
```zig
    exe.addPackage(
        .{
            .name = "clap",
            .path = "libs/zig-clap/clap.zig",
        }
    );
```

Where path is the file path.  Very nice!
 
# Omissions

## Some Confusing Syntax (for beginners)

As someone learning the language, I assume I'm going to bump into confusing things.

In zig the thing I kept bumping into was which line ending to use: ",", ";" or none.

See this exmaple:
```zig
const SyntaxDemo = struct {
    foo: i32 = 1,  // <- comma
    const bar = 12.0; // <- semicolon
    pub fn method() i32 {
        return 13;
    } // <- neither
}; // <- semicolon
```

The compiler errors are not always helpful with these typos/bugs.  For example,
this code:
```zig
const SyntaxDemo = struct {
    foo: i32 = 1;  // <- should be a comma
};
```

produces this error:
```./argparse.zig:27:17: error: expected token '}', found ';'
./syntax_test.zig:27:17: error: expected token '}', found ';'
    foo: i32 = 1;
                ^
```

On the plus side, it notes the character correctly.  On the downside, it says
"expected token is '}', which is not teaching the user what the correct syntax
should be (or why the correct syntax should be what it is supposed to be).

Even in this case:
```zig
const bar = 12.0, // <- semicolon
```

The error message:
```
./syntax_test.zig:28:21: error: expected token ';', found ','
    const bar = 12.0, // <- should be a semicolon
                    ^

```
Says the thing it expects to see, but not why.

## String Class

The big omission from my point of view is that they are missing (intentionally,
it seems) a string class.  By convention, strings in zig are typed as `[] const
u8`.  They also don't seem to have a lot of string processing functions.
Unicode seems to be supported straight up, but it sounds like the implementation
might be in flux, under debate, or otherwise incomplete.

## Keyword Arguments/Default Arguments

Zig doesn't have keyword arguments or default arguments.  Pure opinion, but I
like those language features.

## Documentation

The library documentation is definitely lacking.  A lot of the functions on the
main website are missing docs of any kind, for example:

https://ziglang.org/documentation/0.6.0/std/#std;AutoHashMap

*However* the syntax is so light and it has so little hidden stuff that even
for relative newbies, reading the source for stdlib is surprisingly easy and
understandable:

https://github.com/ziglang/zig/blob/e125ead2b1549eff5bd20c3fb640c9480a9c9aeb/lib/std/hash_map.zig#L51

https://github.com/ziglang/zig/blob/e125ead2b1549eff5bd20c3fb640c9480a9c9aeb/lib/std/hash_map.zig#L317

They're apparently working on documentation generation based on the code docs
but haven't had it working yet.

# Conclusions

I like it!  It worked well for this prototype and I like how understandable it
is.  I wish it had string classes though.

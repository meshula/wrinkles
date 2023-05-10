# How to run `test` blocks in zig in a debugger

## Test Code

For example, you can try this code:

```
pub fn test_fn() void {
var thing: i32 = 3;

_ = thing;

@breakpoint();
}

test "testing breakpoint" {
test_fn();
}
```
I called this file "test_bp.zig".

## Process

1. (optional) put `@breakpoint()` macros in your code where you want to break into the debugger
2. use the `-femit-bin` argument with `zig test` to emit a binary: `zig test test_bp.zig -femit-bin=test_bp`.  In this example, this should produce a binary `test_bp`.
3. get the path to the zig executable: `which zig`
4. run the binary in lldb, passing in the path to the test: 
```
lldb -- ./test_bp `which zig` 
```

After you give lldb the `r` command to run the program, you should see something like:
```
Test [1/1] test "testing breakpoint"... Process 91749 stopped
* thread #1, queue = 'com.apple.main-thread', stop reason = EXC_BREAKPOINT (code=EXC_I386_BPT, subcode=0x0)
    frame #0: 0x0000000100003430 test_main`test_fn at main.zig:1:23
-> 1    pub fn test_fn() void {
   2        var thing: i32 = 3;
   3
   4        _ = thing;
   5
   6        @breakpoint();
   7    }
Target 0: (test_main) stopped.
```

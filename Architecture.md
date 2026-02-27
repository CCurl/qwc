# QWC Architecture Guide

This document provides detailed technical information about QWC's internal architecture, memory layout, and design patterns.

## Memory Layout

QWC manages a single 16MB memory block (`mem[MEM_SZ]`) divided into three regions:

```
 mem[0]             mem[64K CELLS]           mem[MEM_SZ]
+------------------+---------------+-------------------------+
| Compiled code    |   Variables   |   Dictionary Entries    |
| code (grows -->) |   (managed)   |          (<-- grows)    |
+------------------+---------------+-------------------------+
 ^                  ^                                       ^
 compiled code      vars/(vh)       last (dict entry pointer)
 (grows upward)     (user vars)     (grows downward)
```

**Key pointers:**
- `code` (= `&mem[0]`): Start of code area; compiled code lives here
- `here`: Current code allocation position, initialized to `LASTOP+1` (after all primitives)
- `last`: Dictionary entry pointer (grows toward lower addresses from `mem[MEM_SZ]`)
- `vars`: User variable storage starting at 64k cells (64K * CELL_SZ bytes)

**Boundaries:**
- Variables area must not collide with dictionary: `vhere < last`
- Stacks (data, return, loop) grow in their respective arrays; overflow causes undefined behavior

## Dictionary Entry Structure (DE_T)

Each dictionary entry is a variable-length struct:

```c
typedef struct {
    ucell xt;          // Execution token (code address)
    byte sz;           // Entry size (for traversal)
    byte fl;           // Flags
    byte ln;           // Name length
    char nm[1];        // Name (variable length, null-terminated)
    // Padding to 4-byte boundary
} DE_T;
```

**Flags (`fl`):**
- `0x80` (IMMED): Word executes immediately, even during compilation
- `0x40` (INLINE): Definition is copied (inlined) at call site, not called

**Dictionary Entry Size (`sz`):** 
- Includes struct overhead + name + padding
- Used to traverse dictionary: `next_entry = current + sz`

**Example:** Dictionary lookup for word "square" starting at `last` pointer:
```forth
: square dup * ;     ( 3 instructions: DUP, MULT, EXIT )
```
Results in a DE_T at `*last` with `xt` pointing to the compiled code at `here`.

## Literal Encoding

QWC uses two strategies for encoding number literals:

### lit1: Small Literals (Compact)
If `0 <= n <= LIT_BITS`:
- Encodes as: `(n | LIT_MASK)`
- Single CELL stores both opcode and value
- On 64-bit: LIT_MASK = 0x7FF8000000000000 (quiet NaN pattern), LIT_BITS = 0x0007FFFFFFFFFFFF
- On 32-bit: LIT_MASK = 0x40000000, LIT_BITS = 0x3FFFFFFF

### lit2: Large Literals (Fallback)
If `(n < 0) || (n > LIT_BITS`):
- Emits two CELLs: `LIT` opcode followed by the value
- Slower but allows full range

**Why this matters:** lit1 is more efficient (1 instruction vs 2), so the compiler prefers it for small numbers.

## Stack Effects Notation

Stack effect notation in primitive tables and Forth code shows transformations:

| Notation   | Meaning              | Example |
|:--         |:--                   |:-- |
| `(a b--c)` | Pop b, pop a, push c | `+` pops two, pushes sum |
| `(n--)`    | Pop n, discard       | `drop` removes top |
| `(--n)`    | Push n, leave stack  | `key` pushes keypress |
| `(n--n)`   | Non-destructive read | `njmpz` reads TOS, doesn't pop |
| `(--)`     | No stack effect      | `nop` (if it existed) |

**Macros used in the C code:**
- `TOS`: Top of stack (`dstk[dsp]`)
- `NOS`: Next on stack (`dstk[dsp-1]`)
- Operations like `t = pop(); TOS += t;` implement `(a b--c)` pattern

## Compilation State Machine

QWC has three execution states (stored in `state`):

```
  +------+
  v      |
+--INTERP--+         ':'          +--COMPILE--+
|   (0)    |--------------------->|    (1)    |
+----------+                      +-----------+
     ^               ';'                |
     +----------------------------------+

BYE (999) from either state -> EXIT program
```

**INTERPRET (0):**
- Words execute immediately as they're parsed
- Numbers are pushed to stack
- Used in REPL and for immediate words

**COMPILE (1):**
- Words are added to dictionary
- Numbers are compiled as literals
- `:` word triggers this state; `;` returns to INTERPRET
- Only immediate words (flag 0x80) execute during compilation

**Example:**
```forth
5 3 +           ( INTERPRET: pushes 5, 3, adds them, result = 8 )
: foo 5 3 + ;   ( COMPILE: foo defined with code for 5, 3, + )
foo             ( INTERPRET: executes foo, result = 8 )
```

## Common Coding Patterns

### Transient Words (t0-t9)
Used for temporary factoring to avoid cluttering the dictionary:

```forth
: complex  ( x y -- result )
    +L1                    ( create local frame, x -> x@ )
    ... t0 ! ... t0 @      ( use t0 as temp )
    t0 !                   ( reuse t0 in another context )
    ... -L ;
```

**Key:** t0-t9 are reused across different words, not persisted in dictionary.

### Local Variables (+L / -L)
Create a new frame for local variables x, y, z:

```forth
: myword ( a b c -- result )
    +L3                    ( create frame, pop c b a into z y x )
    x@ y@ + z@ *           ( compute: (x + y) * z )
    -L ;
```

**Note:** `+L` allocates a frame on the transient stack (tstk) for x, y, z variables
**Note:** `-L` deallocates the last allocated stack frame.

### Inlining vs Calling
**Inline** (flag 0x40): Definition copied at compile time
```forth
: double dup + ; inline    ( dup + copied to call sites )
: test double double ;     ( compiles: dup + dup + )
```

**Non-inline**: Definition called (slower, smaller code)
```forth
: complex ... ; 
: test complex complex ;   ( compiles: call complex, call complex )
```

## Tail-Call Optimization (TCO)

When a word ends with a call to another word, QWC optimizes:

```forth
: outer ... inner ;        ( calls inner, then EXIT )
: inner ... ;
```

**Without optimization:**
```c
Compiled code for outer:
    ... (inner's code) ...
    CALL inner
    EXIT
```

**With TCO (in `inner()` default case):**
```c
if (code[pc] != EXIT) { rpush(pc); }   // push return only if NOT followed by EXIT
pc = ir;                               // jump to inner directly
goto next;
```

Result: `inner` returns directly to `outer`'s caller, not back to `outer`.

**Why it matters:** Deeply nested tail-recursive words don't exhaust the return stack.

## Dictionary Entry Structure

**NOTE**: `last` refers to the most recently created entry in the dictionary.
Traversing the dictionary from `last` upward:

```c
DE_T *dp = (DE_T *)last;
while (cw < (cell)&mem[MEM_SZ]) {
    if ((dp->ln == ln) && (strEqI(dp->nm, w))) {
        return dp;  // Found!
    }
    cw += dp->sz;  // Move to next entry
    dp = (DE_T *)cw;
}
```

**Debugging:** Print dictionary by walking entries:
```c
for (DE_T *dp = (DE_T *)last; dp < (DE_T *)&mem[MEM_SZ]; dp = (DE_T *)((byte*)dp + dp->sz)) {
    printf("%.*s\n", dp->ln, dp->nm);
}
```

## Error Handling & Limitations

**Stack Safety:**
- No overflow/underflow checks (trusted programmer model)
- Stacks are fixed size (63 entries); exceeding causes memory corruption

**Word Not Found:**
- Parser calls `compileErr()` if word not in dictionary
- Sets `state = INTERPRET` to recover
- Error message: `-word:[name]?-`

**Constraints:**
- Max word name: limited by dictionary allocation
- Max code size: limited by memory (16MB total)
- No exception handling; errors are silent unless checked explicitly

**Trust Model:** QWC assumes well-formed Forth code; invalid operations may crash or corrupt memory.

## Execution Flow: Detailed Example

**Input:** `: double dup + ;`

1. **PARSE:** `outer()` calls `nextWord()`, gets `:` -> sets STATE = COMPILE, calls `addToDict(0)`
2. **DICT ENTRY:** `addToDict()` decrements `last` by entry size to make room, then creates DE_T for "double" at the new `last` location, sets `xt = here`
3. **COMPILE:** Parse `dup`, `+` as primitives, compile their opcodes at `here`, increment `here`
4. **EXIT:** Parse `;` -> compile EXIT opcode, set STATE = INTERPRET

**Invocation:** `3 double`

1. **PARSE NUMBER:** `outer()` calls `nextWord()`, gets "3", calls `isNum()` which converts and pushes 3 to an integer and pushes it onto the stack, returns 1
2. **PARSE WORD:** `nextWord()` gets "double", `findInDict()` returns its DE_T entry
3. **EXECUTE:** STATE == INTERPRET, so `doInterp()` calls `inner()` with the XT for "double"
4. **CALL:** `inner()` jumps to double's XT (location of dup instruction)
5. **DUP:** Duplicates TOS (3, 3)
6. **ADD:** Pops top two entries, pushes sum (6)
7. **EXIT:** Returns from double, control back to outer()
8. **Result:** 6 on stack

This flow shows how primitives, compilation, and execution intertwine in QWC.

# QWC: a very minimal Forth

QWC is a minimal Forth system that can run stand-alone or be embedded into another program.

QWC has 62 base primitives.<br/>
QWC is implemented in 3 files: (qwc-vm.c, qwc-vm.h, system.c). <br/>
The VM itself is under 200 lines of code.

In a QWC program, each instruction is a CELL (32- or 64-bits). <br/>
- If <= the last primitive (system), then it is a primitive.
- Else, if the top 3 bits are set, then it is a literal.
- Else, it is the XT (code address) of a word in the dictionary.

### QWC hard-codes the following IMMEDIATE state-change words:

| Word | Action |
|:--   |:-- |
|  :   | Add the next word to the dictionary, set STATE to COMPILE. |
|  ;   | Compile EXIT and change state to INTERPRET. |

**NOTE**: '(' skips words until the next ')' word.<br/>
**NOTE**: '\\' skips words until the end of the line.<br/>
**NOTE**: Setting state to 999 signals QWC to exit.

## INLINE words

An INLINE word is somewhat similar to a macro in other languages.<br/>
When a word is INLINE, its definition is copied to the target, up to the first `exit`.<br/>
When not INLINE, a call is made to the word instead.

## Transient words

Words 't0' through 't9' are transient and are not added to the dictionary.<br/>
They are case sensitive: 't0' is a transient word, 'T0' is not.<br/>
They help with factoring code and and keep the dictionary uncluttered.

## Built-in variables

There are 3 built-in variables `x`, `y`, and `z`. There is also `+L` and `-L` that<br/>
can be used to create 3 local variables under the user's control. You can use `+L` / `-L`<br/>
at any time for any reason to create a new frame for new versions of the variables.

## QWC Startup Behavior

On startup, QWC does the following:
- Create 'argc' with the count of command-line arguments
- For each argument, create 'argX' with the address of the argument string
- E.G. "arg0 ztype" will print `qwc`
- If arg1 exists and names a file that can be opened, load that file.
- Else, try to load file 'qwc-boot.fth' in the local folder '.'.
- Else, try to load file '`BIN_DIR`qwc-boot.fth' in the "bin" folder.
- On Linux, `BIN_DIR` is "/home/chris/bin/".
- On Windows, `BIN_DIR` is "D:\\bin\\".
- `BIN_DIR` is defined in qwc-vm.h. Change it as appropriate for your system.

## The VM Primitives

| Primitive | Op/Word  | Stack        | Description |
|:--        |:--       |:--           |:-- |
|   0       | exit     | (--)         | PC = R-TOS. Discard R-TOS. If (PC=0) then stop. |
|   1       | lit      | (--)         | Push code[PC]. Increment PC. |
|   2       | jmp      | (--)         | PC = code[PC]. |
|   3       | jmpz     | (n--)        | If (TOS==0) then PC = code[PC] else PC = PC+1. Discard TOS. |
|   4       | jmpnz    | (n--)        | If (TOS!=0) then PC = code[PC] else PC = PC+1. Discard TOS. |
|   5       | njmpz    | (n--n)       | If (TOS==0) then PC = code[PC] else PC = PC+1. |
|   6       | njmpnz   | (n--n)       | If (TOS!=0) then PC = code[PC] else PC = PC+1. |
|   7       | dup      | (n--n n)     | Push TOS. |
|   8       | drop     | (n--)        | Discard TOS. |
|   9       | swap     | (a b--b a)   | Swap TOS and NOS. |
|  10       | over     | (a b--a b a) | Push NOS. |
|  11       | !        | (n a--)      | CELL store NOS through TOS. Discard TOS and NOS. |
|  12       | @        | (a--n)       | CELL fetch TOS through TOS. |
|  13       | c!       | (b a--)      | BYTE store NOS through TOS. Discard TOS and NOS. |
|  14       | c@       | (a--b)       | BYTE fetch TOS through TOS. |
|  15       | >r       | (n--)        | Push TOS onto the return stack. Discard TOS. |
|  16       | r@       | (--n)        | Push R-TOS. |
|  17       | r>       | (--n)        | Push R-TOS. Discard R-TOS. |
|  18       | +L       | (--)         | Create new versions of variables (x,y,z). |
|  19       | -L       | (--)         | Restore the last set of variables. |
|  20       | x!       | (n--)        | Set local variable X to n. |
|  21       | y!       | (n--)        | Set local variable Y to n. |
|  22       | z!       | (n--)        | Set local variable Z to n. |
|  23       | x@       | (--n)        | Push local variable X. |
|  24       | y@       | (--n)        | Push local variable Y. |
|  25       | z@       | (--n)        | Push local variable Z. |
|  26       | x@+      | (--n)        | Push local variable X, then increment it. |
|  27       | y@+      | (--n)        | Push local variable Y, then increment it. |
|  28       | z@+      | (--n)        | Push local variable Z, then increment it. |
|  29       | *        | (a b--c)     | TOS = NOS*TOS. Discard NOS. |
|  30       | +        | (a b--c)     | TOS = NOS+TOS. Discard NOS. |
|  31       | -        | (a b--c)     | TOS = NOS-TOS. Discard NOS. |
|  32       | /mod     | (a b--r q)   | TOS = NOS/TOS. NOS = NOS modulo TOS. |
|  33       | 1+       | (a--b)       | TOS = TOS+1. |
|  34       | 1-       | (a--b)       | TOS = TOS-1. |
|  35       | <        | (a b--f)     | If (NOS<TOS) then TOS = 1 else TOS = 0. Discard NOS. |
|  36       | =        | (a b--f)     | If (NOS=TOS) then TOS = 1 else TOS = 0. Discard NOS. |
|  37       | >        | (a b--f)     | If (NOS<TOS) then TOS = 1 else TOS = 0. Discard NOS. |
|  38       | 0=       | (n--f)       | If (TOS==1) then TOS = 1 else TOS = 0. |
|  39       | +!       | (n a--)      | Add NOS to the cell at TOS. Discard TOS and NOS. |
|  40       | for      | (C--)        | Start a FOR loop starting at 0. Upper limit is C. |
|  41       | i        | (--I)        | Push current loop index. |
|  42       | next     | (--)         | Increment I. If I < C then jump to loop start. |
|  43       | and      | (a b--c)     | TOS = NOS and TOS. Discard NOS. |
|  44       | or       | (a b--c)     | TOS = NOS or  TOS. Discard NOS. |
|  45       | xor      | (a b--c)     | TOS = NOS xor TOS. Discard NOS. |
|  46       | ztype    | (a--)        | Output null-terminated string TOS. Discard TOS. |
|  47       | find     | (--a)        | Push the dictionary address of the next word. |
|  48       | key      | (--n)        | Push the next keypress. Wait if necessary. |
|  49       | key?     | (--f)        | Push 1 if a keypress is available, else 0. |
|  50       | emit     | (c--)        | Output char TOS. Discard TOS. |
|  51       | fopen    | (nm md--fh)  | Open file `nm` using mode `md` (fh=0 if error). |
|  52       | fclose   | (fh--)       | Close file `fh`. Discard TOS. |
|  53       | fread    | (a sz fh--n) | Read `sz` chars from file `fh` to `a`. |
|  54       | fwrite   | (a sz fh--n) | Write `sz` chars to file `fh` from `a`. |
|  55       | ms       | (n--)        | Wait/sleep for TOS milliseconds |
|  56       | timer    | (--n)        | Push the current system time. |
|  57       | add-word | (--)         | Add the next word to the dictionary. |
|  58       | outer    | (a--)        | Run the outer interpreter on TOS. Discard TOS. |
|  59       | cmove    | (f t n--)    | Copy `n` bytes from `f` to `t`. |
|  60       | s-len    | (str--n)     | Determine the length `n` of string `str`. |
|  61       | system   | (str--)      | Execute system(str). Discard TOS. |

## Other built-in words

| Word      | Stack | Description |
|:--        |:--    |:-- |
| version   | (--n) | Current version number. |
| output-fp | (--a) | Address of the output file handle. 0 means STDOUT. |
| (h)       | (--a) | Address of HERE. |
| (l)       | (--a) | Address of LAST. |
| (lsp)     | (--a) | Address of the loop stack pointer. |
| lstk      | (--a) | Address of the loop stack. |
| (rsp)     | (--a) | Address of the return stack pointer. |
| rstk      | (--a) | Address of the return stack. |
| (sp)      | (--a) | Address of the data stack pointer. |
| stk       | (--a) | Address of the data stack. |
| state     | (--a) | Address of STATE. |
| base      | (--a) | Address of BASE. |
| mem       | (--a) | Address of the beginning of the memory area. |
| mem-sz    | (--n) | The number of BYTEs in the memory area. |
| >in       | (--a) | Address of the text input buffer pointer. |
| cell      | (--n) | The size of a CELL in bytes (4 or 8). |

##   Embedding QWC in your C or C++ project

See system.c. It embeds the QWC VM into a C program.

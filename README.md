# todo.asm

To-Do Web Application in [flat assembler](https://flatassembler.net/) for Linux x86_64.

https://github.com/tsoding/todo.asm/assets/165283/414c2083-a17f-4069-a6fb-2fa4a1b4be76

## Features

- Single completely self-contained static executable (depends only on Linux x86_64 kernel);
- Includes its own simple HTTP Server listening to port 6969 (hardcoded);
- Frontend works without JavaScript (HTML forms only, like in good old days);
- XSS support in case you still want to have JavaScript on the Frontend;

## Quick Start

Install [flat assembler](https://flatassembler.net/)

```console
$ fasm ./todo.asm
$ chmod +x ./todo
$ ./todo
$ iexplore http://localhost:6969/
```

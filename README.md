# hscript-typer

A simple static type checker for [HScript](https://github.com/FunkinCrew/hscript/).

This library provides a basic typer for HScript, enabling limited type checking and inference for scripts written using the HScript language in Haxe.

## Installation

Install via haxelib:

```bash
haxelib install hscript-typer
```

## Usage

```haxe
import hscript.Parser;
import hscript.Interp;
import hscript.typer.Typer;
import hscript.typer.TypedExpr;

using hscript.typer.TypedExprTools;

class Main {
    static function main() {
        var code:String = 'var a = 12.5; var b = 5; var c = a + b;';
        var parser:Parser = new Parser();
        parser.allowTypes = true;
        var e:Expr = parser.parseString(code);
        var interp:Interp = new Interp();
        var typer:Typer = new Typer(interp);
        var te:TypedExpr = typer.type(e, code);
        trace('Successfully typed expression!: ${te.toString()}');
    }
}
```

## Features

- Basic type inference and checking for HScript expressions
- Support for variable declarations, operations, conditionals, and more

## Limitations

- Type checking is limited and may not cover all Haxe language features
- Currently no null safety

## Contributing

Feel free to open issues or submit pull requests if you'd like to improve the typer or help expand its capabilities.

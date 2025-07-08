package hscript.typer;

import hscript.Expr;
import hscript.Printer;

class TypedExprTools
{
  // TODO: add tabs + make code more readable + fix some stuff
  public static function toString(e:TypedExpr, printTypes:Bool):String
  {
    var str:String = switch (e.e)
    {
      case TEConst(c):
        switch (c)
        {
          case CInt(v):
            '${v}';
          case CFloat(f):
            '${f}';
          case CString(s):
            s;
        }
      case TEIdent(v):
        v;
      case TEVar(n, t, e1):
        'var ${n}${t != null ? ':${typeToString(t)}' : ''}${e1 != null ? ' = ${toString(e1, printTypes)}' : ''}';
      case TEParent(e1):
        '(${toString(e1, printTypes)})';
      case TEBlock(es):
        es.length > 0 ? '{\n${[for (e in es) toString(e, printTypes)].join(';\n')}\n}' : '{}';
      case TEField(e1, f):
        '${toString(e1, printTypes)}.${f}';
      case TEBinop(op, e1, e2):
        '${toString(e1, printTypes)} ${op} ${toString(e2, printTypes)}';
      case TEUnop(op, prefix, e1):
        '${prefix ? op : ''}${toString(e1, printTypes)}${!prefix ? op : ''}';
      case TECall(e1, params):
        '${toString(e1, printTypes)}(${[for (p in params) toString(p, printTypes)].join(', ')})';
      case TEIf(cond, e1, e2):
        'if (${toString(cond, printTypes)}) ${toString(e1, printTypes)}${e2 != null ? ' else ${toString(e2, printTypes)}' : ''}';
      case TEWhile(cond, e1):
        'while (${toString(cond, printTypes)}) ${toString(e1, printTypes)}';
      case TEFor(v, it, e1):
        'for (${v} in ${toString(it, printTypes)}) ${toString(e1, printTypes)}';
      case TEBreak:
        'break';
      case TEContinue:
        'continue';
      case TEFunction(args, e1, name, ret):
        'function${name != null ? ' ${name}' : ''}(${[for (a in args) '${a.opt != null && a.opt ? '?' : ''}${a.name}:${typeToString(a.t)}${a.value != null ? ' = ${toString(a.value, printTypes)}' : ''}'].join(', ')})${ret != null ? ':${typeToString(ret)}' : ''} ${toString(e1, printTypes)}';
      case TEReturn(e1):
        'return${e1 != null ? ' ${toString(e1, printTypes)}' : ''}';
      case TEArray(e1, index):
        '${toString(e1, printTypes)}[${toString(index, printTypes)}]';
      case TEArrayDecl(es):
        '[${[for (e in es) toString(e, printTypes)].join(', ')}]';
      case TENew(cl, params):
        'new ${cl}(${[for (p in params) toString(p, printTypes)].join(', ')})';
      case TEThrow(e1):
        'throw ${toString(e1, printTypes)}';
      case TETry(e1, v, t, ecatch):
        'try ${toString(e1, printTypes)} catch(${v}${t != null ? ':${typeToString(t)}' : ''}) ${toString(ecatch, printTypes)}';
      case TEObject(fl):
        '{\n${[for (f in fl) '${f.name}: ${toString(f.e, printTypes)}'].join(',\n')}\n}';
      case TETernary(cond, e1, e2):
        '${toString(cond, printTypes)} ? ${toString(e1, printTypes)} : ${toString(e2, printTypes)}';
      case TESwitch(e1, cases, defaultExpr):
        'switch (${toString(e1, printTypes)}) {\n${[for (c in cases) 'case ${[for (v in c.values) toString(v, printTypes)].join(' | ')}: ${toString(c.expr, printTypes)}'].join('\n')}${defaultExpr != null ? '\ndefault: ${toString(defaultExpr, printTypes)}' : ''}\n}';
      case TEDoWhile(cond, e1):
        'do ${toString(e1, printTypes)} while (${toString(cond, printTypes)})';
      case TEMeta(name, args, e1):
        '@${name}${args.length > 0 ? '(${[for (a in args) toString(a, printTypes)].join(', ')})' : ''} ${toString(e1, printTypes)}';
      case TECheckType(e1, t):
        '${toString(e1, printTypes)}:${typeToString(t)}';
      case TEForGen(it, e1):
        'for (${toString(it, printTypes)}) ${toString(e1, printTypes)}';
      default:
        return '<invalid>';
    }
    return printTypes ? '(${typeToString(e.t)}: ${str})' : str;
  }

  static function typeToString(t:CType):String
  {
    return new Printer().typeToString(t);
  }
}

package hscript.typer;

import hscript.Expr;
import hscript.Printer;

class TypedExprTools
{
  static final TAB:String = '  ';

  public static function toString(e:TypedExpr, printTypes:Bool = true):String
  {
    var str:String = '';
    switch (e.e)
    {
      case TEConst(c):
        switch (c)
        {
          case CInt(v):
            str += '${v}';
          case CFloat(f):
            str += '${f}';
          case CString(s):
            str += '"${s}"';
        }
      case TEIdent(v):
        str += v;
      case TEVar(n, t, e1):
        str += 'var ${n}';
        if (t != null) str += ':${typeToString(t)}';
        if (e1 != null) str += ' = ${toString(e1, printTypes)}';
      case TEParent(e1):
        str += '(${toString(e1, printTypes)})';
      case TEBlock(es):
        if (es.length > 0)
        {
          str += '{\n';
          str += applyTab([for (e in es) '${toString(e, printTypes)};'].join('\n'));
          str += '\n}';
        }
        else
        {
          str += '{}';
        }
      case TEField(e1, f):
        str += '${toString(e1, printTypes)}.${f}';
      case TEBinop(op, e1, e2):
        str += '${toString(e1, printTypes)} ${op} ${toString(e2, printTypes)}';
      case TEUnop(op, prefix, e1):
        if (prefix) str += op;
        str += toString(e1, printTypes);
        if (!prefix) str += op;
      case TECall(e1, params):
        str += toString(e1, printTypes);
        str += '(';
        str += [for (p in params) toString(p, printTypes)].join(', ');
        str += ')';
      case TEIf(cond, e1, e2):
        str += 'if (${toString(cond, printTypes)}) ';
        str += toString(e1, printTypes);
        if (e2 != null) str += ' else ${toString(e2, printTypes)}';
      case TEWhile(cond, e1):
        str += 'while (${toString(cond, printTypes)}) ${toString(e1, printTypes)}';
      case TEFor(v, it, e1):
        str += 'for (${v} in ${toString(it, printTypes)}) ${toString(e1, printTypes)}';
      case TEBreak:
        str += 'break';
      case TEContinue:
        str += 'continue';
      case TEFunction(args, e1, name, ret):
        str += 'function';
        if (name != null) str += ' ${name}';
        str += '(';
        for (i => a in args)
        {
          if (a.opt != null && a.opt) str += '?';
          str += '${a.name}:${typeToString(a.t)}';
          if (a.value != null) str += ' = ${toString(a.value, printTypes)}';
          if (i != args.length - 1) str += ', ';
        }
        str += ')';
        if (ret != null) str += ':${typeToString(ret)}';
        str += ' ${toString(e1, printTypes)}';
      case TEReturn(e1):
        str += 'return';
        if (e1 != null) str += ' ${toString(e1, printTypes)}';
      case TEArray(e1, index):
        str += '${toString(e1, printTypes)}[${toString(index, printTypes)}]';
      case TEArrayDecl(es):
        str += '[${[for (e in es) toString(e, printTypes)].join(', ')}]';
      case TENew(cl, params):
        str += 'new ${cl}(${[for (p in params) toString(p, printTypes)].join(', ')})';
      case TEThrow(e1):
        str += 'throw ${toString(e1, printTypes)}';
      case TETry(e1, v, t, ecatch):
        str += 'try ${toString(e1, printTypes)} ';
        str += 'catch(${v}';
        if (t != null) str += ':${typeToString(t)}';
        str += ') ${toString(ecatch, printTypes)}';
      case TEObject(fl):
        str += '{\n${applyTab([for (f in fl) '${f.name}: ${toString(f.e, printTypes)}'].join(',\n'))}\n}';
      case TETernary(cond, e1, e2):
        str += '${toString(cond, printTypes)} ? ${toString(e1, printTypes)} : ${toString(e2, printTypes)}';
      case TESwitch(e1, cases, defaultExpr):
        str += 'switch (${toString(e1, printTypes)}) {\n';
        str += [
          for (c in cases)
            'case ${[for (v in c.values) toString(v, printTypes)].join(' | ')}: ${toString(c.expr, printTypes)}'
        ].join('\n');
        if (defaultExpr != null) str += '\ndefault: ${toString(defaultExpr, printTypes)}';
        str += '\n}';
      case TEDoWhile(cond, e1):
        str += 'do ${toString(e1, printTypes)} while (${toString(cond, printTypes)})';
      case TEMeta(name, args, e1):
        str += '@${name}';
        if (args.length > 0) str += [for (a in args) exprtToString(a)].join(', ');
        str += ' ${toString(e1, printTypes)}';
      case TECheckType(e1, t):
        str += '${toString(e1, printTypes)}:${typeToString(t)}';
      case TEForGen(it, e1):
        str += 'for (${toString(it, printTypes)}) ${toString(e1, printTypes)}';
    }
    return printTypes ? '(${typeToString(e.t)}: ${str})' : str;
  }

  static function typeToString(t:CType):String
  {
    return new Printer().typeToString(t);
  }

  static function exprtToString(e:Expr):String
  {
    return new Printer().exprToString(e);
  }

  static function applyTab(s:String):String
  {
    return [for (l in s.split('\n')) '${TAB}${l}'].join('\n');
  }
}

package hscript.validator;

import hscript.Printer;
import hscript.Interp;
import hscript.Tools;
import hscript.Expr;

class Validator
{
  var interp:Interp;
  var locals:Map<String, CType>;

  public function new(interp:Interp)
  {
    this.interp = interp;
    this.locals = new Map<String, CType>();
  }

  public function validate(e:Expr):Void
  {
    switch (Tools.expr(e))
    {
      case EVar(n, t1, e1):
        if (t1 == null && e1 == null) error(e, 'Needs to have a type or be initialized');
        var t:Null<CType> = t1;
        if (e1 != null)
        {
          var et:CType = typeof(e1);
          if (t != null && !equalType(et, t)) error(e, 'Cannot assign ${typeToString(et)} to ${typeToString(t1)}');
          else if (t == null) t = et;
        }
        locals.set(n, t);
      case EBlock(exprs):
        for (e in exprs)
          validate(e);
      case EBinop(op, e1, e2):
        // `in` is also an binary operator this will later be handled in the EFor and EForGen
        var t1:CType = typeof(e1);
        var t2:CType = typeof(e2);

        if (['+', '-', '*', '/'].contains(op) && (!isNumerical(t1) || !isNumerical(t2))) error(e,
          'operands are of different types: ${typeToString(t1)} ${op} ${typeToString(t2)}');
        if (['<<', '>>'].contains(op)) if (t2 != builtin('Int')) error(e, 'bitshift operator needs to be Int, but got ${typeToString(t2)}');
        if (!equalType(t1, t2)) error(e, 'operands are of different types: ${typeToString(t1)} ${op} ${typeToString(t2)}');
      default:
    }
  }

  function typeof(e:Expr):CType
  {
    switch (Tools.expr(e))
    {
      case EConst(c):
        switch (c)
        {
          case CInt(_):
            return builtin('Int');
          case CFloat(_):
            return builtin('Float');
          case CString(_):
            return builtin('String');
        }
      case EIdent(v):
        if (locals.exists(v)) return locals.get(v);
        if (interp.variables.exists(v)) return builtin('Dynamic');
        return error(e, '${v} does not exist');
      case EVar(_, _, _):
        return builtin('Void');
      case EParent(e1):
        return typeof(e1);
      case EBlock(e1):
        if (e1.length > 0) return typeof(e1[e1.length - 1]);
        return builtin('Void');
      case EField(e1, f):
        return error(e1, 'Will think about this later');
      case EBinop(op, e1, e2):
        // `in` is also an binary operator this will later be handled in the EFor and EForGen
        var t1:CType = typeof(e1);
        var t2:CType = typeof(e2);
        if (equalType(t1, t2)) return t1;
        if (['+', '-', '*', '/'].contains(op) && isNumerical(t1) && isNumerical(t2)) return builtin('Float');
        if (['<<', '>>'].contains(op))
        {
          if (equalType(t2, builtin('Int'))) return t1;
          return error(e, 'bitshift operator needs to be Int, but got ${typeToString(t2)}');
        }
        return error(e, 'operands are of different types: ${typeToString(t1)} ${op} ${typeToString(t2)}');
      case EUnop(_, _, e1):
        return typeof(e1);
      case ECall(e1, _):
        var t:CType = typeof(e1);
        switch (t)
        {
          case CTFun(_, ret):
            return ret;
          default:
            throw 'Should be a function type: ${e1}';
        }
      case EIf(_, e1, e2):
        var t1:CType = typeof(e1);
        var t2:CType = typeof(e2);
        if (equalType(t1, t2)) return t1;
        return builtin('Dynamic');
      case EWhile(_, _):
        return builtin('Void');
      case EFor(_, _, _):
        return builtin('Void');
      case EBreak:
        return builtin('Void');
      case EContinue:
        return builtin('Void');
      case EFunction(args, _, _, ret):
        var targs:Array<CType> = [];
        for (a in args)
        {
          if (a.t == null) return error(e, 'Function argument ${a.name} needs a type');
          var t:CType = a.opt != null && a.opt ? CTOpt(a.t) : a.t;
          targs.push(CTNamed(a.name, t));
        }
        if (ret == null) return error(e, 'Function needs a return type');
        return CTFun(targs, ret);
      case EReturn(e1):
        if (e1 == null) return builtin('Void');
        return typeof(e1);
      case EArray(e1, _):
        var t:CType = typeof(e1);
        switch (t)
        {
          case CTPath(['Array'], [p]):
            return p;
          default:
            throw 'Should be an Array type: ${e}';
        }
      case EArrayDecl(exprs):
        if (exprs.length == 0) return CTPath(['Array'], [CTPath(['?'], null)]);
        var t:CType = typeof(exprs[0]);
        for (e1 in exprs)
        {
          var t1:CType = typeof(e1);
          if (equalType(t, t1))
          {
            if (isNumerical(t) && isNumerical(t1)) t = builtin('Float');
            else
              return CTPath(['Array'], [builtin('Dynamic')]);
          }
        }
        return t;
      case ENew(cl, _):
        return CTPath([cl], null);
      case EThrow(_):
        return builtin('Void');
      case ETry(e1, _, _, e2):
        var t1:CType = typeof(e1);
        var t2:CType = typeof(e2);
        if (equalType(t1, t2)) return t1;
        if (isNumerical(t1) && isNumerical(t2)) return builtin('Float');
        return builtin('Dynamic');
      case EObject(fl):
        return CTAnon([for (f in fl) {name: f.name, t: typeof(f.e)}]);
      case ETernary(_, e1, e2):
        var t1:CType = typeof(e1);
        var t2:CType = typeof(e2);
        if (equalType(t1, t2)) return t1;
        if (isNumerical(t1) && isNumerical(t2)) return builtin('Float');
        return builtin('Dynamic');
      case ESwitch(_, cases, defaultExpr):
        var t:CType = defaultExpr != null ? typeof(defaultExpr) : typeof(cases[0].expr);
        var exprs = cases.copy();
        for (c in exprs)
        {
          var t1:CType = typeof(c.expr);
          if (equalType(t, t1))
          {
            if (isNumerical(t) && isNumerical(t1)) t = builtin('Float');
            else
              return builtin('Dynamic');
          }
        }
        return t;
      case EDoWhile(_, _):
        return builtin('Void');
      case EMeta(_, _, _):
        return builtin('Void');
      case ECheckType(_, t):
        return t;
      case EForGen(_, _):
        return builtin('Void');
      default:
        throw 'Expr not yet handled: ${e}';
    }
  }

  function isNumerical(t:CType):Bool
  {
    switch (t)
    {
      case CTPath(['Int'], _) | CTPath(['Float'], _):
        return true;
      default:
        return false;
    }
  }

  function equalType(t1:CType, t2:CType):Bool
  {
    switch [t1, t2]
    {
      case [CTPath(p1, ps1), CTPath(p2, ps2)]:
        if (p1.length != p2.length) return false;
        if (ps1 != null && ps2 == null) return false;
        if (ps2 != null && ps1 == null) return false;
        if (ps1 != null && ps2 != null && ps1.length != ps2.length) return false;
        for (i in 0...p1.length)
          if (p1[i] != p2[i]) return false;
        if (ps1 != null && ps2 != null) for (i in 0...ps1.length)
          if (equalType(ps1[i], ps2[i])) return false;
        return true;
      default:
        return false;
    }
  }

  function typeToString(t:CType):String
  {
    return new Printer().typeToString(t);
  }

  function builtin(t:String):CType
  {
    return CTPath([t], null);
  }

  function error(e:Expr, m:String):Null<Dynamic>
  {
    #if hscriptPos
    throw '${e.origin}: ${e.line}: ${m}';
    #else
    throw 'hscript-validator: ${m}';
    #end
    return null;
  }
}

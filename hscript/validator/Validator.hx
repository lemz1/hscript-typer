package hscript.validator;

import hscript.Printer;
import hscript.Interp;
import hscript.Tools;
import hscript.Expr;

class Validator
{
  var interp:Interp;
  var locals:Map<String, CType>;
  var declared:Array<{n:String, old:Null<CType>}>;
  var cachedBlockTypes:Map<Expr, CType>;

  public function new(interp:Interp)
  {
    this.interp = interp;
    this.locals = new Map<String, CType>();
    this.declared = [];
    this.cachedBlockTypes = new Map<Expr, CType>();
  }

  public function validate(e:Expr):Void
  {
    locals.clear();
    declared = [];
    validateTypeof(e);
  }

  function validateTypeof(e:Expr):CType
  {
    switch (Tools.expr(e))
    {
      case EVar(n, t1, e1):
        var t:Null<CType> = t1;
        if (e1 != null)
        {
          var et:CType = validateTypeof(e1);
          if (t != null && !equalType(et,
            t) && !equalType(t,
              builtin('Float')) && !equalType(et, builtin('Int'))) return error(e, 'Cannot assign ${typeToString(et)} to ${typeToString(t1)}');
          else if (t == null) t = et;
        }
        if (t == null) return error(e, '${n} needs to have a type or be initialized');
        add(n, t);
      case EIdent(v):
        if (!locals.exists(v) && !interp.variables.exists(v)) return error(e, '${v} does not exist');
      case EParent(e1):
        validateTypeof(e1);
      case EBlock(exprs):
        var old:Int = declared.length;
        for (e1 in exprs)
          validateTypeof(e1);
        typeof(e); // cache block type
        restore(old);
      case EField(e1, f):
        return error(e1, 'Will think about this later');
      case EBinop(op, e1, e2):
        var t1:CType = validateTypeof(e1);
        var t2:CType = validateTypeof(e2);
        if (!equalType(t1, t2))
        {
          if (['=', '+=', '-=', '*=', '/='].contains(op)) if (!equalType(t1,
            builtin('Float')) || !equalType(t2,
              builtin('Int'))) return error(e, 'operands are of different types: ${typeToString(t1)} ${op} ${typeToString(t2)}');
          else if (['+', '-', '*', '/'].contains(op)) if ((!isNumerical(t1) || !isNumerical(t2))) return error(e,
            'operands are of different types: ${typeToString(t1)} ${op} ${typeToString(t2)}');
          else if (['<<', '>>'].contains(op)) if (t2 != builtin('Int')) return error(e, 'bitshift operator needs to be Int, but got ${typeToString(t2)}');
          else
            return error(e, 'operands are of different types: ${typeToString(t1)} ${op} ${typeToString(t2)}');
        }
      case ECall(e1, params):
        var t:CType = validateTypeof(e1);
        switch (t)
        {
          case CTFun(args, _):
            if (params.length > args.length) return error(e, 'Call has too many arguments: expected ${args.length} but got ${params.length}');
            for (i in 0...params.length)
            {
              var pt:CType = validateTypeof(params[i]);
              if (!equalType(pt, args[i])
                && !equalType(args[i], builtin('Float'))
                && !equalType(pt, builtin('Int'))) return error(e, 'Got ${typeToString(pt)} but wants ${typeToString(args[i])}');
            }
          case CTPath(['Dynamic'], null):
            // Dynamic will not be checked
          default:
            throw 'Should be a function type';
        }
      case EIf(cond, e1, e2):
        var ct:CType = validateTypeof(cond);
        if (!equalType(ct, builtin('Bool'))) return error(e, 'Condition must return a Bool');
        // expr could not be a block, but still declare a local variable so we make sure to restore locals
        var old:Int = declared.length;
        validateTypeof(e1);
        restore(old);
        var old:Int = declared.length;
        validateTypeof(e2);
        restore(old);
      case EWhile(cond, e1):
        var ct:CType = validateTypeof(cond);
        if (!equalType(ct, builtin('Bool'))) return error(e, 'Condition must return a Bool');
        // expr could not be a block, but still declare a local variable so we make sure to restore locals
        var old:Int = declared.length;
        validateTypeof(e1);
        restore(old);
      case EFor(v, it, e1):
        var old:Int = declared.length;
        var itt:CType = typeof(it);
        switch (itt)
        {
          case CTPath(['Array'], [p1]):
            add(v, p1);
          default:
            var fields:Array<String> = Type.getInstanceFields(Type.resolveClass(typeToString(itt)));
            if (!fields.contains('iterator') || !fields.contains('keyValueIterator')) return error(e, '${typeToString(itt)} needs to be iterable');
            add(v, builtin('Dynamic'));
        };
        validateTypeof(e1);
        restore(old);
      case EFunction(args, e1, name, ret):
        var targs:Array<CType> = [];
        for (a in args)
        {
          if (a.t == null) return error(e, 'Function argument ${a.name} needs a type');
          var t:CType = a.opt != null && a.opt ? CTOpt(a.t) : a.t;
          targs.push(CTNamed(a.name, t));
          add(a.name, t);
        }
        if (ret == null) return error(e, 'Function needs a return type');
        var t:CType = CTFun(targs, ret);
        add(name, t);
        var old:Int = declared.length;
        restore(old);
      default:
    }
    return typeof(e);
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
      case EBlock(exprs):
        if (cachedBlockTypes.exists(e)) return cachedBlockTypes.get(e);
        if (exprs.length > 0)
        {
          var t:CType = typeof(exprs[exprs.length - 1]);
          cachedBlockTypes.set(e, t);
          return t;
        }
        return builtin('Void');
      case EField(e1, f):
        return error(e1, 'Will think about this later');
      case EBinop(op, e1, e2):
        var t1:CType = typeof(e1);
        var t2:CType = typeof(e2);
        if (equalType(t1, t2)) return t1;
        if (['=', '+=', '-=', '*=', '/='].contains(op) && equalType(t1, builtin('Float')) && equalType(t2, builtin('Int'))) return t1;
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
          case CTPath(['Dynamic'], null):
            return builtin('Dynamic');
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
      case EFunction(args, _, name, ret):
        var targs:Array<CType> = [];
        for (a in args)
        {
          if (a.t == null) return error(e, 'Function argument ${a.name} needs a type');
          var t:CType = a.opt != null && a.opt ? CTOpt(a.t) : a.t;
          targs.push(CTNamed(a.name, t));
        }
        if (ret == null) return error(e, 'Function needs a return type');
        var t:CType = CTFun(targs, ret);
        add(name, t);
        return t;
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
        return CTPath(['Array'], [t]);
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

  function add(n:String, t:Null<CType>):Void
  {
    declared.push(
      {
        n: n,
        old: locals.get(n)
      });
    locals.set(n, t);
  }

  function restore(length:Int):Void
  {
    if (declared.length < length) throw 'How did this happen';

    while (declared.length > length)
    {
      var decl = declared.pop();
      if (decl.old != null) locals.set(decl.n, decl.old);
      else
        locals.remove(decl.n);
    }
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

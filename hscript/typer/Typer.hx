package hscript.typer;

import hscript.typer.TypedExpr;
import hscript.Printer;
import hscript.Interp;
import hscript.Tools;
import hscript.Expr;

using StringTools;

class Typer
{
  /**
   * If the type of a variable could not be deduced, until it is used, it will fallback to `Dynamic`
   */
  public var variablesFallbackToDynamic:Bool = false;

  /**
   * If the type of a function argument is not given, it will fallback to `Dynamic`
   */
  public var argumentsFallbackToDynamic:Bool = false;

  /**
   * If the return type of a function is not given, it will fallback to `Dynamic`
   */
  public var returnsFallbackToDynamic:Bool = false;

  var interp:Interp;
  var locals:Map<String, CType>;
  var declared:Array<{n:String, old:Null<CType>}>;

  var code:Null<String>;

  public function new(interp:Interp)
  {
    this.interp = interp;
    this.locals = new Map<String, CType>();
    this.declared = [];
    this.code = null;
  }

  /**
   * Types the given expression and returns it
   * @param e The expression to type
   * @return The typed expression
   */
  public function type(e:Expr):TypedExpr
  {
    var t:TypedExpr = typeExpr(e);
    this.locals.clear();
    this.declared = [];
    return t;
  }

  /**
   * Types the given modules
   * @param modules An array of modules to type
   */
  public function typeModules(modules:Array<TyperModule>):Void {}

  /**
   * Checks whether typing errors occur in the given module
   * @param code The code for better error messages
   */
  public function validateModules(?code:String):Void {}

  var canBreakOrContinue:Bool = false;

  /**
   * Checks whether typing errors occur in the given expression
   * @param e The typed expression to validate
   * @param code The code for better error messages
   */
  public function validate(e:TypedExpr, ?code:String):Void
  {
    this.code = code;
    validateExpr(e);
    this.code = null;
  }

  function validateExpr(e:TypedExpr):Void
  {
    switch (e.e)
    {
      case TEConst(_):
      case TEIdent(v):
        if (isUnknown(e.t)) error(e, 'Local variable "${v}" used without being initialized');
      case TEVar(n, t, e1):
        if (e1 != null) validateExpr(e1);
        if (e1 != null && t != null && !equalType(t, e1.t) && !(isFloat(t) && isInt(e1.t)) && !(isDynamic(t) || isDynamic(e1.t)))
        {
          if (equalType(e1.t, CTPath(['Array'], [unknown()])))
          {
            switch (t)
            {
              case CTPath(['Array'], [_]):
              default:
                error(e1, '"${typeToString(e1.t)}" should be "${typeToString(t)}"');
            }
          }
          else if (!isNull(t) && isNull(e1.t))
          {
            error(e1, '"${typeToString(e1.t)}" should be "${typeToString(t)}"');
          }
        }
        if (e1 != null && (t == null || (t != null && !isDynamic(t))))
        {
          if (isDynamic(e1.t))
          {
            switch (e1.e)
            {
              case TETernary(_, _, _) | TEIf(_, _, _):
                if (t == null)
                {
                  error(e, 'Type of local variable "${n}" needs to be explicitly set to "Dynamic"');
                }
                else
                {
                  error(e1, '"Dynamic" should be "${typeToString(t)}"');
                }
              default:
            }
          }
          else if (t == null && equalType(e1.t, CTPath(['Array'], [CTPath(['Dynamic'], null)])))
          {
            error(e, 'Type of local variable "${n}" needs to be explicitly set to "Array<Dynamic>"');
          }
        }
      case TEParent(e1):
        validateExpr(e1);
      case TEBlock(es):
        for (e1 in es)
          validateExpr(e1);
      case TEField(e1, f):
        validateExpr(e1);
        if (isUnknown(e.t)) error(e, '"${typeToString(e1.t)}" has no field" ${f}"');
      case TEBinop(op, e1, e2):
        validateExpr(e1);
        validateExpr(e2);
        if (!equalType(e1.t, e2.t) && !(isDynamic(e1.t) || isDynamic(e2.t)))
        {
          if ((!isFloat(commonType(e1.t, e2.t)) && !equalType(getNullInner(e1.t), getNullInner(e2.t)))
            || (['=', '+=', '-=', '*=', '/='].contains(op) && (isInt(e1.t) || (!isNull(e1.t) && isNull(e2.t)))))
          {
            error(e2, '"${typeToString(e2.t)}" should be "${typeToString(e1.t)}"');
          }
        }
      case TEUnop(op, prefix, e1):
        validateExpr(e1);
        if (!isInt(e1.t)) error(e1, '"${typeToString(e1.t)}" should be "Int"');
      case TECall(e1, params):
        validateExpr(e1);
        switch (e1.t)
        {
          case CTFun(args, _):
            var requiredArgs:Int = 0;
            for (a in args)
            {
              switch (a)
              {
                case CTOpt(_):
                default:
                  requiredArgs++;
              }
            }
            if (params.length < requiredArgs) error(e, 'Expected atleast ${requiredArgs} argument(s) but got ${params.length}');
            else if (params.length > args.length) error(e, 'Expected ${args.length} argument(s) but got ${params.length}');
            for (i in 0...params.length)
            {
              validateExpr(params[i]);
              if (!equalType(params[i].t, args[i])
                && !(isFloat(args[i]) && isInt(params[i].t))
                && !(isDynamic(params[i].t) || isDynamic(args[i]))) error(params[i], '"${typeToString(params[i].t)}" should be "${typeToString(args[i])}"');
            }
          default:
            for (p in params)
              validateExpr(p);
        }
      case TEIf(cond, e1, e2):
        validateExpr(cond);
        if (!isBool(cond.t)) error(cond, '"${typeToString(cond.t)}" should be "Bool"');
        validateExpr(e1);
        validateExpr(e2);
      case TEWhile(cond, e1):
        validateExpr(cond);
        canBreakOrContinue = true;
        if (!isBool(cond.t)) error(cond, '"${typeToString(cond.t)}" should be "Bool"');
        validateExpr(e1);
        canBreakOrContinue = false;
      case TEFor(v, it, e1):
        validateExpr(it);
        canBreakOrContinue = true;
        validateExpr(e1);
        canBreakOrContinue = false;
      case TEBreak:
        if (!canBreakOrContinue) error(e, 'Break outside loop');
      case TEContinue:
        if (!canBreakOrContinue) error(e, 'Continue outside loop');
      case TEFunction(args, e1, name, ret):
        for (a in args)
          if (isUnknown(a.t)) error(e, 'Argument "${a.name}" needs to have a type');
        if (ret == null || isUnknown(ret)) error(e, 'Function${name != null ? ' "${name}"' : ''} needs a return type');
        validateExpr(e1);
        if (!equalType(e1.t,
          ret) && !(isFloat(ret) && isInt(e1.t)) && !(isDynamic(e1.t) || isDynamic(ret))) error(e1, '"${typeToString(e1.t)}" should be "${typeToString(ret)}"');
      case TEReturn(e1):
        if (e1 != null) validateExpr(e1);
      case TEArray(e1, index):
        validateExpr(e1);
        validateExpr(index);
      case TEArrayDecl(es):
        for (e1 in es)
          validateExpr(e1);
      case TENew(cl, params):
        var cls:Class<Dynamic> = Type.resolveClass(cl);
        if (cls == null) error(e, 'Class "${cl}" does not exist');
        for (p in params)
          validateExpr(p);
      case TEThrow(e1):
        validateExpr(e1);
      case TETry(e1, v, t, ecatch):
        validateExpr(e1);
        if (t == null || isUnknown(t)) error(e, 'Caught error "${v}" needs to have a type');
        validateExpr(ecatch);
      case TEObject(fl):
        for (f in fl)
          validateExpr(f.e);
      case TETernary(cond, e1, e2):
        validateExpr(cond);
        if (!isBool(cond.t)) error(cond, '"${typeToString(cond.t)}" should be "Bool"');
        validateExpr(e1);
        validateExpr(e2);
      case TESwitch(e1, cases, defaultExpr):
        validateExpr(e1);
        for (c in cases)
        {
          for (v in c.values)
          {
            validateExpr(v);
            if (!equalType(e1.t, v.t) && (!isFloat(e1.t) && !isInt(v.t)) && (!isDynamic(e1.t) || !isDynamic(v.t)))
            {
              error(v, '"${typeToString(v.t)}" should be "${typeToString(e1.t)}"');
            }
          }
          validateExpr(c.expr);
        }
        if (defaultExpr != null) validateExpr(defaultExpr);
      case TEDoWhile(cond, e1):
        validateExpr(cond);
        canBreakOrContinue = true;
        if (!isBool(cond.t)) error(cond, '"${typeToString(cond.t)}" should be "Bool"');
        validateExpr(e1);
        canBreakOrContinue = false;
      case TEMeta(name, args, e1):
        for (a in args)
          validateExpr(a);
        validateExpr(e1);
      case TECheckType(e1, t):
        validateExpr(e1);
        if (!equalType(e1.t, t)) error(e, '"${typeToString(e1.t)}" should be "${typeToString(t)}"');
      case TEForGen(it, e1):
        validateExpr(it);
        validateExpr(e1);
    }
  }

  function typeExpr(e:Expr):TypedExpr
  {
    switch (Tools.expr(e))
    {
      case EConst(c):
        var t:CType = switch (c)
        {
          case CInt(_): builtin('Int');
          case CFloat(_): builtin('Float');
          case CString(_): builtin('String');
        }
        return buildTypedExpr(e, TEConst(c), t);
      case EIdent(v):
        var t:CType = if (['true', 'false'].contains(v))
        {
          builtin('Bool');
        }
        else if (v == 'null')
        {
          CTPath(['Null'], [unknown()]);
        }
        else if (locals.exists(v))
        {
          if (isUnknown(locals.get(v)) && variablesFallbackToDynamic) locals.set(v, builtin('Dynamic'));
          locals.get(v);
        }
        else if (interp.variables.exists(v))
        {
          builtin('Dynamic');
        }
        else
        {
          unknown();
        }
        return buildTypedExpr(e, TEIdent(v), t);
      case EVar(n, t, e1):
        var te1:Null<TypedExpr> = e1 != null ? typeExpr(e1) : null;
        if (t != null && isNullUnknown(te1.t)) te1.t = buildNull(t);
        add(n, t ?? te1?.t ?? unknown());
        return buildTypedExpr(e, TEVar(n, t, te1), builtin('Void'));
      case EParent(e1):
        var te1:TypedExpr = typeExpr(e1);
        return buildTypedExpr(e, TEParent(te1), te1.t);
      case EBlock(es):
        var old:Int = declared.length;
        var tes:Array<TypedExpr> = [for (e1 in es) typeExpr(e1)];
        var t:CType = tes.length > 0 ? tes[tes.length - 1].t : builtin('Void');
        restore(old);
        return buildTypedExpr(e, TEBlock(tes), t);
      case EField(e1, f):
        var te1:TypedExpr = typeExpr(e1);
        var t:CType = getFieldType(te1.t, f);
        return buildTypedExpr(e, TEField(te1, f), t);
      case EBinop(op, e1, e2):
        var te1:TypedExpr = typeExpr(e1);
        var te2:TypedExpr = typeExpr(e2);
        if (op == '=' && (isUnknown(te1.t) || isNullUnknown(te1.t)))
        {
          switch (te1.e)
          {
            case TEIdent(te1v):
              if (locals.exists(te1v))
              {
                var t:CType = isNullUnknown(te1.t) ? buildNull(te2.t) : te2.t;
                locals.set(te1v, t);
                te1.t = t;
              }
            default:
              throw 'Pretty sure this should not happen: ${te1.e}';
          }
        }
        if (isNullUnknown(te1.t)) te1.t = buildNull(te2.t);
        else if (isNullUnknown(te2.t)) te2.t = buildNull(te1.t);
        var t:CType = ['==', '!='].contains(op) ? builtin('Bool') : commonType(te1.t, te2.t);
        return buildTypedExpr(e, TEBinop(op, te1, te2), t);
      case EUnop(op, prefix, e1):
        var te1:TypedExpr = typeExpr(e1);
        return buildTypedExpr(e, TEUnop(op, prefix, te1), te1.t);
      case ECall(e1, params):
        var te1:TypedExpr = typeExpr(e1);
        var tparams:Array<TypedExpr> = [for (p in params) typeExpr(p)];
        var t:CType = equalType(te1.t, builtin('Dynamic')) ? te1.t : switch (te1.t)
        {
          case CTFun(_, ret): ret;
          default: unknown();
        }
        return buildTypedExpr(e, TECall(te1, tparams), t);
      case EIf(cond, e1, e2):
        var tcond:TypedExpr = typeExpr(cond);
        var old:Int = declared.length;
        var te1:TypedExpr = typeExpr(e1);
        restore(old);
        var old:Int = declared.length;
        var te2:Null<TypedExpr> = e2 != null ? typeExpr(e2) : null;
        restore(old);
        if (isNullUnknown(te1.t)) te1.t = buildNull(te2.t);
        else if (isNullUnknown(te2.t)) te2.t = buildNull(te1.t);
        var t:CType = te2 != null ? commonType(te1.t, te2.t) : te1.t;
        return buildTypedExpr(e, TEIf(tcond, te1, te2), t);
      case EWhile(cond, e1):
        var tcond:TypedExpr = typeExpr(cond);
        var old:Int = declared.length;
        var te1:TypedExpr = typeExpr(e1);
        restore(old);
        return buildTypedExpr(e, TEWhile(tcond, te1), builtin('Void'));
      case EFor(v, it, e1):
        var old:Int = declared.length;
        var tit:TypedExpr = typeExpr(it);
        var vt:CType = getIterable(tit.t) ?? unknown();
        add(v, vt);
        var te1:TypedExpr = typeExpr(e1);
        restore(old);
        return buildTypedExpr(e, TEFor(v, tit, te1), te1.t);
      case EBreak:
        return buildTypedExpr(e, TEBreak, builtin('Void'));
      case EContinue:
        return buildTypedExpr(e, TEContinue, builtin('Void'));
      case EFunction(args, e1, name, ret):
        var targs:Array<TypedArgument> = [
          for (a in args)
            {
              name: a.name,
              t: a.t ?? (argumentsFallbackToDynamic ? builtin('Dynamic') : unknown()),
              opt: a.opt,
              value: a.value != null ? typeExpr(a.value) : null
            }
        ];
        var old:Int = declared.length;
        for (ta in targs)
          add(ta.name, ta.t);
        var te1:TypedExpr = typeExpr(e1);
        restore(old);
        var tret:CType = ret ?? (returnsFallbackToDynamic ? builtin('Dynamic') : unknown());
        var t:CType = CTFun([for (ta in targs) ta.t], tret);
        return buildTypedExpr(e, TEFunction(targs, te1, name, tret), t);
      case EReturn(e1):
        var te1:Null<TypedExpr> = e1 != null ? typeExpr(e1) : null;
        var t:CType = te1.t ?? builtin('Void');
        return buildTypedExpr(e, TEReturn(te1), t);
      case EArray(e1, index):
        var te1:TypedExpr = typeExpr(e1);
        var tindex:TypedExpr = typeExpr(index);
        var t:CType = getIterable(te1.t) ?? unknown();
        return buildTypedExpr(e, TEArray(te1, tindex), t);
      case EArrayDecl(es):
        var tes:Array<TypedExpr> = [for (e1 in es) typeExpr(e1)];
        var et:CType = unknown();
        if (tes.length > 0)
        {
          var t:CType = tes[0].t;
          for (i in 1...tes.length)
            t = commonType(t, tes[i].t);
          et = t;
        }
        var t:CType = CTPath(['Array'], [et]);
        return buildTypedExpr(e, TEArrayDecl(tes), t);
      case ENew(cl, params):
        var tparams:Array<TypedExpr> = [for (p in params) typeExpr(p)];
        return buildTypedExpr(e, TENew(cl, tparams), builtin('Dynamic'));
      case EThrow(e1):
        var te1:TypedExpr = typeExpr(e1);
        return buildTypedExpr(e, TEThrow(te1), builtin('Void'));
      case ETry(e1, v, t1, ecatch):
        var te1:TypedExpr = typeExpr(e1);
        var tecatch:TypedExpr = typeExpr(ecatch);
        var t:CType = commonType(te1.t, tecatch.t);
        return buildTypedExpr(e, TETry(te1, v, t1, tecatch), t);
      case EObject(fl):
        var tfl:Array<{name:String, e:TypedExpr}> = [for (f in fl) {name: f.name, e: typeExpr(f.e)}];
        var t:CType = CTAnon([for (tf in tfl) {name: tf.name, t: tf.e.t}]);
        return buildTypedExpr(e, TEObject(tfl), t);
      case ETernary(cond, e1, e2):
        var tcond:TypedExpr = typeExpr(cond);
        var te1:TypedExpr = typeExpr(e1);
        var te2:TypedExpr = typeExpr(e2);
        if (isNullUnknown(te1.t)) te1.t = buildNull(te2.t);
        else if (isNullUnknown(te2.t)) te2.t = buildNull(te1.t);
        var t:CType = commonType(te1.t, te2.t);
        return buildTypedExpr(e, TETernary(tcond, te1, te2), t);
      case ESwitch(e1, cases, defaultExpr):
        var te1:TypedExpr = typeExpr(e1);
        var tcases:Array<{values:Array<TypedExpr>, expr:TypedExpr}> = [
          for (c in cases)
            {
              values: [for (v in c.values) typeExpr(v)],
              expr: typeExpr(c.expr)
            }
        ];
        var tdefaultExpr:Null<TypedExpr> = defaultExpr != null ? typeExpr(defaultExpr) : null;
        var t:CType = builtin('Dynamic');
        if (tdefaultExpr != null) t = tdefaultExpr.t;
        if (tcases.length > 0)
        {
          var ct:CType = tcases[0].expr.t;
          for (i in 1...tcases.length)
            ct = commonType(ct, tcases[i].expr.t);
          t = ct;
        }
        return buildTypedExpr(e, TESwitch(te1, tcases, tdefaultExpr), t);
      case EDoWhile(cond, e1):
        var tcond:TypedExpr = typeExpr(cond);
        var te1:TypedExpr = typeExpr(e1);
        return buildTypedExpr(e, TEDoWhile(tcond, te1), builtin('Void'));
      case EMeta(name, args, e1):
        var targs:Array<TypedExpr> = [for (a in args) typeExpr(a)];
        var te1:TypedExpr = typeExpr(e1);
        return buildTypedExpr(e, TEMeta(name, targs, te1), builtin('Void'));
      case ECheckType(e1, t):
        var te1:TypedExpr = typeExpr(e1);
        return buildTypedExpr(e, TECheckType(te1, t), builtin('Void'));
      case EForGen(it, e1):
        var tit:TypedExpr = typeExpr(it);
        var te1:TypedExpr = typeExpr(e1);
        return buildTypedExpr(e, TEForGen(tit, te1), te1.t);
    }
  }

  function getIterable(t:CType):Null<CType>
  {
    switch (t)
    {
      case CTPath(['Array'], [p]):
        return p;
      default:
        return null;
    }
  }

  function getFieldType(t:CType, f:String):CType
  {
    function _getFieldType(t:CType, f:String, instance:Bool):CType
    {
      switch (t)
      {
        case CTPath(path, _):
          var dottedPath:String = path.join('.');
          var cls:Class<Dynamic> = Type.resolveClass(dottedPath);
          if (cls == null) return unknown();
          var fs:Array<String> = instance ? Type.getInstanceFields(cls) : Type.getClassFields(cls);
          if (!fs.contains(f)) return unknown();
          return builtin('Dynamic');
        default:
          return unknown();
      }
    }

    switch (t)
    {
      case CTPath(path, params):
        var dottedPath:String = path.join('.');
        if (dottedPath == 'Class') return _getFieldType(params[0], f, false);
        return _getFieldType(t, f, true);
      case CTParent(t1):
        return getFieldType(t1, f);
      case CTOpt(t1):
        return getFieldType(t1, f);
      case CTNamed(_, t1):
        return getFieldType(t1, f);
      default:
        return unknown();
    }
  }

  function commonType(t1:CType, t2:CType):CType
  {
    if (equalType(t1, t2)) return t1;
    else if (equalType(getNullInner(t1), getNullInner(t2))) return buildNull(t1);
    else if (isNumber(t1) && isNumber(t2)) return builtin('Float');
    else
      return builtin('Dynamic');
  }

  function buildNull(t:CType):CType
  {
    return isNull(t) ? t : CTPath(['Null'], [t]);
  }

  function getNullInner(t:CType):CType
  {
    switch (t)
    {
      case CTPath(['Null'], [p]):
        return p;
      default:
        return t;
    }
  }

  function isNullUnknown(t:CType):Bool
  {
    switch (t)
    {
      case CTPath(['Null'], [p]):
        return isUnknown(p);
      default:
        return false;
    }
  }

  function isNull(t:CType):Bool
  {
    switch (t)
    {
      case CTPath(['Null'], [_]):
        return true;
      default:
        return false;
    }
  }

  function isNumber(t:CType):Bool
  {
    return equalType(t, builtin('Int')) || equalType(t, builtin('Float'));
  }

  function isDynamic(t:CType):Bool
  {
    return equalType(t, builtin('Dynamic'));
  }

  function isFloat(t:CType):Bool
  {
    return equalType(t, builtin('Float'));
  }

  function isInt(t:CType):Bool
  {
    return equalType(t, builtin('Int'));
  }

  function isBool(t:CType):Bool
  {
    return equalType(t, builtin('Bool'));
  }

  function isUnknown(t:CType):Bool
  {
    return equalType(t, unknown());
  }

  function unknown():CType
  {
    return builtin('?');
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
          if (!equalType(ps1[i], ps2[i])) return false;
        return true;
      case [CTFun(args1, ret1), CTFun(args2, ret2)]:
        if (args1.length != args2.length) return false;
        if (!equalType(ret1, ret2)) return false;
        for (i in 0...args1.length)
          if (!equalType(args1[i], args2[i])) return false;
        return true;
      case [CTAnon(fields1), CTAnon(fields2)]:
        if (fields1.length != fields2.length) return false;
        for (i in 0...fields1.length)
        {
          if (fields1[i].name != fields2[i].name) return false;
          if (fields1[i].t != fields2[i].t) return false;
          if (fields1[i].meta != fields2[i].meta) return false;
        }
        return true;
      case [CTParent(t1), CTParent(t2)]:
        if (!equalType(t1, t2)) return false;
        return true;
      case [CTOpt(t1), CTOpt(t2)]:
        if (!equalType(t1, t2)) return false;
        return true;
      case [CTNamed(n1, t1), CTNamed(n2, t2)]:
        if (n1 != n2) return false;
        if (!equalType(t1, t2)) return false;
        return true;
      case [CTExpr(e1), CTExpr(e2)]: // TODO
        return false;
      default:
        return false;
    }
  }

  function buildTypedExpr(e:Expr, te:TypedExprDef, t:CType):TypedExpr
  {
    return {
      e: te,
      t: t,
      #if hscriptPos
      pmin: e.pmin, pmax: e.pmax, origin: e.origin, line: e.line,
      #end
    };
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

  function typeToString(t:CType):String
  {
    return new Printer().typeToString(t);
  }

  function error(e:TypedExpr, m:String):Void
  {
    #if hscriptPos
    throw new TyperError(m, e.origin, e.line, e.pmin, e.pmax, code);
    #else
    throw new TyperError(m);
    #end
  }
}

class TyperError extends haxe.Exception
{
  public var origin(default, null):Null<String>;
  public var line(default, null):Null<Int>;
  public var pmin(default, null):Null<Int>;
  public var pmax(default, null):Null<Int>;
  public var code(default, null):Null<String>;

  public function new(message:String, ?origin:String, ?line:Int, ?pmin:Int, ?pmax:Int, ?code:String)
  {
    super(message);
    this.origin = origin;
    this.line = line;
    this.pmin = pmin;
    this.pmax = pmax;
    this.code = code;
  }

  override public function toString():String
  {
    if (origin == null || line == null || pmin == null || pmax == null) return message;
    if (code != null)
    {
      var absolutePos:Int = 0;
      var lineIndex:Int = 0;
      for (i in 0...code.length)
      {
        if (lineIndex == line - 1) break;
        if (code.charAt(absolutePos++) == '\n') lineIndex++;
      }
      var relativePos:Int = pmin - absolutePos;
      var length:Int = pmax - pmin;
      var squigglyLine:String = ''.rpad(' ', relativePos).rpad('~', relativePos + length + 1);
      return '${origin}:${line}: characters ${relativePos + 1}-${relativePos + length + 1} : ${message}\n${code.split('\n')[lineIndex]}\n${squigglyLine}';
    }
    else
    {
      return '${origin}:${line}: characters ${pmin}-${pmax} : ${message}';
    }
  }
}

typedef TyperModule = Array<ModuleDecl>;

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
   * If the type of a function argument is not given, it will fallback to `Dynamic`
   */
  public var argumentsFallbackToDynamic:Bool = false;

  /**
   * If the return type of a function is not given, it will fallback to `Dynamic`
   */
  public var returnsFallbackToDynamic:Bool = false;

  var interp:Interp;
  var members:Map<String, CType>;
  var locals:Map<String, CType>;
  var declared:Array<{n:String, old:Null<CType>}>;

  var pack:Array<String>;
  var imports:Map<String, CType>;
  var everythingImports:Array<Array<String>>;
  var scriptedTypes:Map<String, ModuleDecl>;

  var canBreakOrContinue:Bool;
  var requiredReturnType:CType;

  var code:Null<String>;
  var origin:Null<String>;

  public function new(interp:Interp)
  {
    this.interp = interp;
    this.members = new Map<String, CType>();
    this.locals = new Map<String, CType>();
    this.declared = [];
    this.pack = [];
    this.imports = new Map<String, CType>();
    this.everythingImports = [];
    this.scriptedTypes = new Map<String, ModuleDecl>();
    this.canBreakOrContinue = false;
    this.requiredReturnType = builtin('Void');
    this.code = null;
    this.origin = null;
  }

  /**
   * Types the given expression and returns it
   * @param e The expression to type
   * @param code The code for better error messages
   * @return The typed expression
   */
  public function type(e:Expr, ?code:String):TypedExpr
  {
    this.code = code;

    var t:TypedExpr = typeExpr(e);

    locals.clear();
    declared = [];
    canBreakOrContinue = false;
    requiredReturnType = builtin('Void');
    this.code = null;

    return t;
  }

  /**
   * Types the given modules
   * @param modules An array of modules to type
   * @return The typed modules
   */
  public function typeModules(modules:Array<TyperModule>):Array<TypedModuleDecl>
  {
    for (m in modules)
      retrieveScriptedTypes(m);

    var tmodules:Array<TypedModuleDecl> = [];
    for (m in modules)
      tmodules = tmodules.concat(typeModule(m));

    pack = [];
    imports.clear();
    everythingImports = [];
    scriptedTypes.clear();

    return tmodules;
  }

  function retrieveScriptedTypes(m:TyperModule):Void
  {
    origin = m.origin;

    var canSetPack:Bool = true;
    var canSetImport:Bool = true;
    for (d in m.decls)
    {
      switch (d)
      {
        case DPackage(path):
          if (!canSetPack) moduleError('"package" needs to be the first expression in the module');
          pack = path;
          for (i in 0...pack.length)
            everythingImports.push(pack.slice(0, i + 1));

        case DImport(path, everything, name):
          if (!canSetImport) moduleError('"import" and "using" may not appear after a declaration');
          canSetPack = false;
          if (everything ?? false)
          {
            everythingImports.push(pack);
          }
          else
          {
            var name:String = name ?? path[path.length - 1];
            imports.set(name, CTPath(path, null));
          }

        case DClass(c):
          canSetPack = false;
          canSetImport = false;
          scriptedTypes.set(getFullPath(c.name), d);

        case DTypedef(c):
          canSetPack = false;
          canSetImport = false;
          scriptedTypes.set(getFullPath(c.name), d);

        case DEnum(e):
          canSetPack = false;
          canSetImport = false;
          scriptedTypes.set(getFullPath(e.name), d);
      }
    }

    pack = [];
    imports.clear();
    everythingImports = [];
    origin = null;
  }

  function typeModule(m:TyperModule):Array<TypedModuleDecl>
  {
    origin = m.origin;

    var tmodules:Array<TypedModuleDecl> = [];
    for (d in m.decls)
    {
      switch (d)
      {
        case DPackage(path):
          pack = path;
          for (i in 0...pack.length)
            everythingImports.push(pack.slice(0, i + 1));
          tmodules.push(TDPackage(path));

        case DImport(path, everything, name):
          if (everything ?? false)
          {
            everythingImports.push(path);
          }
          else
          {
            var name:String = name ?? path[path.length - 1];
            imports.set(name, CTPath(path, null));
          }
          tmodules.push(TDImport(path, everything, name));

        case DClass(c):
          members.clear();
          var vars:Array<FieldDecl> = [];
          var funs:Array<FieldDecl> = [];
          for (fd in c.fields)
          {
            switch (fd.kind)
            {
              case KVar(_):
                vars.push(fd);

              case KFunction(_):
                funs.push(fd);
            }
          }

          var tfields:Array<TypedFieldDecl> = [];
          for (fd in vars.concat(funs))
          {
            if (members.exists(fd.name)) moduleError('"${getFullPath(c.name)}.${fd.name}" declared twice');

            var tkind:TypedFieldKind = switch (fd.kind)
            {
              case KFunction(f):
                var targs:Array<TypedArgument> = [
                  for (a in f.args)
                    {
                      name: a.name,
                      t: a.t ?? (argumentsFallbackToDynamic ? builtin('Dynamic') : moduleError('Argument "${a.name}" inside "${getFullPath(c.name)}.${fd.name}" needs to have a type')),
                      opt: a.opt,
                      value: a.value != null ? type(a.value, m.code) : null
                    }
                ];
                for (ta in targs)
                  if (!typeIsValid(ta.t)) moduleError('"${typeToString(ta.t)}" is not valid ("${getFullPath(c.name)}.${fd.name}")');
                var tret:CType = f.ret ?? (fd.name == 'new' ? builtin('Void') : (returnsFallbackToDynamic ? builtin('Dynamic') : moduleError('"${getFullPath(c.name)}.${fd.name}" needs to have a return type')));
                if (!typeIsValid(tret)) moduleError('"${typeToString(tret)}" is not valid ("${getFullPath(c.name)}.${fd.name}")');
                var oldRet:CType = requiredReturnType;
                requiredReturnType = tret;
                var texpr:TypedExpr = type(f.expr, m.code);
                requiredReturnType = oldRet;
                var t:CType = CTFun([for (ta in targs) ta.t], tret);
                members.set(fd.name, t);
                TKFunction({args: targs, expr: texpr, ret: tret});

              case KVar(v):
                if (v.get != null
                  && !['default', 'get', 'never'].contains(v.get))
                  moduleError('Property accessor "${v.get}" in "${getFullPath(c.name)}.${fd.name}" does not exist');
                if (v.set != null
                  && !['default', 'set', 'never'].contains(v.set))
                  moduleError('Property accessor "${v.set}" in "${getFullPath(c.name)}.${fd.name}" does not exist');
                if (v.type == null && v.expr == null) moduleError('"${getFullPath(c.name)}.${fd.name}" needs to have a type or be initialized');
                if (v.type != null && !typeIsValid(v.type)) moduleError('"${typeToString(v.type)}" is not a valid type');
                var texpr:Null<TypedExpr> = v.expr != null ? type(v.expr, m.code) : null;
                if (texpr != null && !typeIsValid(texpr.t)) moduleExprError(v.expr, '"${typeToString(texpr.t)}" is not a valid type', m.code);
                if (texpr != null
                  && v.type != null
                  && !equalType(v.type, texpr.t)
                  && !(isFloat(v.type) && isInt(texpr.t))
                  && !(isDynamic(v.type) || isDynamic(texpr.t)))
                {
                  if (equalType(texpr.t, CTPath(['Array'], [unknown()])))
                  {
                    switch (v.type)
                    {
                      case CTPath(['Array'], [_]):
                      default:
                        moduleExprError(v.expr, '"${typeToString(texpr.t)}" should be "${typeToString(v.type)}"', m.code);
                    }
                  }
                  else
                  {
                    moduleExprError(v.expr, '"${typeToString(texpr.t)}" should be "${typeToString(v.type)}"', m.code);
                  }
                }
                if (texpr != null && (v.type == null || (v.type != null && !isDynamic(v.type))))
                {
                  if (isDynamic(texpr.t))
                  {
                    switch (texpr.e)
                    {
                      case TETernary(_, _, _) | TEIf(_, _, _):
                        if (v.type == null)
                        {
                          moduleError('Type of variable "${getFullPath(c.name)}.${fd.name}" needs to be explicitly set to "Dynamic"');
                        }
                        else
                        {
                          moduleExprError(v.expr, '"Dynamic" should be "${typeToString(v.type)}"', m.code);
                        }
                      default:
                    }
                  }
                  else if (v.type == null && equalType(texpr.t, CTPath(['Array'], [builtin('Dynamic')])))
                  {
                    moduleError('Type of variable "${getFullPath(c.name)}.${fd.name}" needs to be explicitly set to "Array<Dynamic>"');
                  }
                }
                var t:CType = v.type ?? texpr.t;
                members.set(fd.name, t);
                TKVar(
                  {
                    get: v.get,
                    set: v.set,
                    expr: texpr,
                    type: t
                  });
            };

            tfields.push(
              {
                name: fd.name,
                meta: fd.meta,
                kind: tkind,
                access: fd.access
              });
          }

          tmodules.push(TDClass(
            {
              name: c.name,
              params: c.params,
              meta: c.meta,
              isPrivate: c.isPrivate,
              extend: c.extend,
              implement: c.implement,
              fields: tfields,
              isExtern: c.isExtern
            }));

        case DTypedef(c):
          tmodules.push(TDTypedef(c));

        case DEnum(e):
          tmodules.push(TDEnum(e));
      }
    }

    pack = [];
    imports.clear();
    everythingImports = [];
    origin = null;

    return tmodules;
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
        else if (v == 'this') // TODO
        {
          builtin('Dynamic');
        }
        else if (locals.exists(v))
        {
          if (isUnknown(locals.get(v))) error(e, 'Local variable "${v}" used without being initialized');
          locals.get(v);
        }
        else if (members.exists(v))
        {
          members.get(v);
        }
        else if (interp.variables.exists(v))
        {
          builtin('Dynamic');
        }
        else
        {
          var type:Dynamic = resolveType(v) ?? error(e, 'Unknown identifier "${v}"');
          resolvedTypeToCType(type);
        }
        return buildTypedExpr(e, TEIdent(v), t);

      case EVar(n, t, e1):
        if (t != null && !typeIsValid(t)) error(e, '"${typeToString(t)}" is not a valid type');

        var te1:Null<TypedExpr> = e1 != null ? typeExpr(e1) : null;
        if (t != null && isNullUnknown(te1.t)) te1.t = t;
        add(n, t ?? te1?.t ?? unknown());

        if (te1 != null && t != null && !equalType(t, te1.t) && !(isFloat(t) && isInt(te1.t)) && !(isDynamic(t) || isDynamic(te1.t)))
        {
          if (equalType(te1.t, CTPath(['Array'], [unknown()])))
          {
            switch (t)
            {
              case CTPath(['Array'], [_]):
              default:
                error(e1, '"${typeToString(te1.t)}" should be "${typeToString(t)}"');
            }
          }
          else
          {
            error(e1, '"${typeToString(te1.t)}" should be "${typeToString(t)}"');
          }
        }
        if (te1 != null && (t == null || (t != null && !isDynamic(t))))
        {
          if (isDynamic(te1.t))
          {
            switch (te1.e)
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
          else if (t == null && equalType(te1.t, CTPath(['Array'], [builtin('Dynamic')])))
          {
            error(e, 'Type of local variable "${n}" needs to be explicitly set to "Array<Dynamic>"');
          }
        }

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
        // typing...
        var te1:Null<TypedExpr> = null;
        var efield:Expr = e1;
        var typePack:Array<String> = [];
        #if hscriptPos
        var pmin:Int = efield.pmin;
        #end
        while (efield != null)
        {
          switch (Tools.expr(efield))
          {
            case EIdent(v):
              typePack.insert(0, v);
              var path:String = typePack.join('.');
              #if hscriptPos
              var ne:Expr =
                {
                  e: EIdent(path),
                  pmin: pmin,
                  pmax: efield.pmax,
                  origin: efield.origin,
                  line: efield.line,
                };
              #else
              var ne:Expr = EIdent(path);
              #end
              var type:Dynamic = resolveType(path);
              if (type != null)
              {
                var t:CType = resolvedTypeToCType(type);
                te1 = buildTypedExpr(ne, TEIdent(path), t);
              }
              break;
            case EField(e2, f2):
              typePack.insert(0, f2);
              efield = e2;
            default:
              efield = null;
          }
        }

        te1 ??= typeExpr(e1);

        if (!isDynamic(te1.t))
        {
          var fields:Array<String> = [];
          var isStatic:Bool = false;
          switch (te1.t)
          {
            case CTPath(['Class'], [p]) | CTPath(['Enum'], [p]):
              fields = getFields(p)?.statics ?? error(e1, 'Could not get fields for type "${typeToString(p)}"');
              isStatic = true;
            default:
              fields = getFields(te1.t)?.fields ?? error(e1, 'Could not get fields for type "${typeToString(te1.t)}"');
              isStatic = false;
          }
          if (!fields.contains(f)) error(e, '"${typeToString(te1.t)}" has no${isStatic ? ' static ' : ' instance '}field "${f}"');
        }

        return buildTypedExpr(e, TEField(te1, f), builtin('Dynamic'));

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
                var t:CType = te2.t;
                locals.set(te1v, t);
                te1.t = t;
              }
            default:
              throw 'Pretty sure this should not happen: ${te1.e}';
          }
        }
        if (isNullUnknown(te1.t)) te1.t = te2.t;
        else if (isNullUnknown(te2.t)) te2.t = te1.t;
        var t:CType = ['==', '!='].contains(op) ? builtin('Bool') : commonType(te1.t, te2.t);

        if (!equalType(te1.t, te2.t) && !(isDynamic(te1.t) || isDynamic(te2.t)))
        {
          if ((!isFloat(commonType(te1.t, te2.t)) && !equalType(te1.t, te2.t))
            || (['=', '+=', '-=', '*=', '/='].contains(op) && isInt(te1.t)))
          {
            error(e2, '"${typeToString(te2.t)}" should be "${typeToString(te1.t)}"');
          }
        }

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

        switch (te1.t)
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
            if (tparams.length < requiredArgs) error(e, 'Expected atleast ${requiredArgs} argument(s) but got ${tparams.length}');
            else if (tparams.length > args.length) error(e, 'Expected ${args.length} argument(s) but got ${tparams.length}');
            for (i in 0...tparams.length)
            {
              if (!equalType(tparams[i].t, args[i])
                && !(isFloat(args[i]) && isInt(tparams[i].t))
                && !(isDynamic(tparams[i].t) || isDynamic(args[i])))
              {
                error(params[i], '"${typeToString(tparams[i].t)}" should be "${typeToString(args[i])}"');
              }
            }
          default:
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
        if (isNullUnknown(te1.t)) te1.t = te2.t;
        else if (isNullUnknown(te2.t)) te2.t = te1.t;
        var t:CType = te2 != null ? commonType(te1.t, te2.t) : te1.t;

        if (!isBool(tcond.t)) error(cond, '"${typeToString(tcond.t)}" should be "Bool"');

        return buildTypedExpr(e, TEIf(tcond, te1, te2), t);

      case EWhile(cond, e1):
        var tcond:TypedExpr = typeExpr(cond);
        var old:Int = declared.length;
        canBreakOrContinue = true;
        var te1:TypedExpr = typeExpr(e1);
        canBreakOrContinue = false;
        restore(old);

        if (!isBool(tcond.t)) error(cond, '"${typeToString(tcond.t)}" should be "Bool"');

        return buildTypedExpr(e, TEWhile(tcond, te1), builtin('Void'));

      case EFor(v, it, e1):
        var old:Int = declared.length;
        var tit:TypedExpr = typeExpr(it);
        var vt:CType = getIterable(tit.t) ?? error(it, '"${typeToString(tit.t)}" needs to be iterable');
        add(v, vt);
        canBreakOrContinue = true;
        var te1:TypedExpr = typeExpr(e1);
        canBreakOrContinue = false;
        restore(old);
        return buildTypedExpr(e, TEFor(v, tit, te1), te1.t);

      case EBreak:
        if (!canBreakOrContinue) error(e, 'Break outside loop');
        return buildTypedExpr(e, TEBreak, builtin('Void'));

      case EContinue:
        if (!canBreakOrContinue) error(e, 'Continue outside loop');
        return buildTypedExpr(e, TEContinue, builtin('Void'));

      case EFunction(args, e1, name, ret):
        var targs:Array<TypedArgument> = [
          for (a in args)
            {
              name: a.name,
              t: a.t ?? (argumentsFallbackToDynamic ? builtin('Dynamic') : error(e, 'Argument "${a.name}" needs to have a type')),
              opt: a.opt,
              value: a.value != null ? typeExpr(a.value) : null
            }
        ];
        for (ta in targs)
          if (!typeIsValid(ta.t)) error(e, '"${typeToString(ta.t)}" is not a valid type');
        var tret:CType = ret ?? (returnsFallbackToDynamic ? builtin('Dynamic') : error(e, 'Function needs to have a return type'));
        if (!typeIsValid(tret)) error(e, '"${typeToString(tret)}" is not a valid type');
        var oldRequiredReturnType:CType = requiredReturnType;
        requiredReturnType = tret;
        var old:Int = declared.length;
        for (ta in targs)
          add(ta.name, ta.t);
        var te1:TypedExpr = typeExpr(e1);
        restore(old);
        requiredReturnType = oldRequiredReturnType;
        var t:CType = CTFun([for (ta in targs) ta.t], tret);

        if (!equalType(te1.t, tret) && !(isFloat(tret) && isInt(te1.t)) && !(isDynamic(te1.t) || isDynamic(tret)))
        {
          error(e1, '"${typeToString(te1.t)}" should be "${typeToString(tret)}"');
        }

        return buildTypedExpr(e, TEFunction(targs, te1, name, tret), t);

      case EReturn(e1):
        var te1:Null<TypedExpr> = e1 != null ? typeExpr(e1) : null;
        var t:CType = te1?.t ?? builtin('Void');

        if (!equalType(requiredReturnType, t) && !(isFloat(requiredReturnType) && isInt(t)))
        {
          error(e, '"${typeToString(t)}" should be "${typeToString(requiredReturnType)}"');
        }

        return buildTypedExpr(e, TEReturn(te1), t);

      case EArray(e1, index):
        var te1:TypedExpr = typeExpr(e1);
        var tindex:TypedExpr = typeExpr(index);
        var t:CType = getIterable(te1.t) ?? error(e1, '"${typeToString(te1.t)}" needs to be iterable');

        if (!isInt(tindex.t))
        {
          error(index, '"${typeToString(tindex.t)}" should be Int');
        }

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

        var cls:Dynamic = resolveType(cl);
        if (cls == null) error(e, 'Class "${cl}" does not exist');
        var t:CType = resolvedTypeToCType(cls);
        switch (t)
        {
          case CTPath(['Class'], [p]):
            t = p;
          default:
        }

        return buildTypedExpr(e, TENew(cl, tparams), t);

      case EThrow(e1):
        var te1:TypedExpr = typeExpr(e1);
        return buildTypedExpr(e, TEThrow(te1), builtin('Void'));

      case ETry(e1, v, t1, ecatch):
        var te1:TypedExpr = typeExpr(e1);
        var tecatch:TypedExpr = typeExpr(ecatch);
        var t:CType = commonType(te1.t, tecatch.t);

        if (t1 == null) error(e, 'Caught error "${v}" needs to have a type');
        if (!typeIsValid(t1)) error(e, '"${typeToString(t1)}" is not a valid type');

        return buildTypedExpr(e, TETry(te1, v, t1, tecatch), t);

      case EObject(fl):
        var tfl:Array<{name:String, e:TypedExpr}> = [for (f in fl) {name: f.name, e: typeExpr(f.e)}];
        var t:CType = CTAnon([for (tf in tfl) {name: tf.name, t: tf.e.t}]);
        return buildTypedExpr(e, TEObject(tfl), t);

      case ETernary(cond, e1, e2):
        var tcond:TypedExpr = typeExpr(cond);
        var te1:TypedExpr = typeExpr(e1);
        var te2:TypedExpr = typeExpr(e2);
        if (isNullUnknown(te1.t)) te1.t = te2.t;
        else if (isNullUnknown(te2.t)) te2.t = te1.t;
        var t:CType = commonType(te1.t, te2.t);

        if (!isBool(tcond.t)) error(cond, '"${typeToString(tcond.t)}" should be "Bool"');

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

        for (i => tc in tcases)
        {
          for (j => tv in tc.values)
          {
            if (!equalType(te1.t, tv.t) && (!isFloat(te1.t) && !isInt(tv.t)) && (!isDynamic(te1.t) || !isDynamic(tv.t)))
            {
              error(cases[i].values[j], '"${typeToString(tv.t)}" should be "${typeToString(te1.t)}"');
            }
          }
        }

        return buildTypedExpr(e, TESwitch(te1, tcases, tdefaultExpr), t);

      case EDoWhile(cond, e1):
        var tcond:TypedExpr = typeExpr(cond);
        var te1:TypedExpr = typeExpr(e1);

        if (!isBool(tcond.t)) error(cond, '"${typeToString(tcond.t)}" should be "Bool"');

        return buildTypedExpr(e, TEDoWhile(tcond, te1), builtin('Void'));

      case EMeta(name, args, e1):
        var te1:TypedExpr = typeExpr(e1);
        return buildTypedExpr(e, TEMeta(name, args, te1), builtin('Void'));

      case ECheckType(e1, t):
        var te1:TypedExpr = typeExpr(e1);

        if (!typeIsValid(t)) error(e, '"${typeToString(t)}" is not a valid type');
        if (!equalType(te1.t, t)) error(e, '"${typeToString(te1.t)}" should be "${typeToString(t)}"');

        return buildTypedExpr(e, TECheckType(te1, t), t);

      case EForGen(it, e1):
        var tit:TypedExpr = typeExpr(it);
        var te1:TypedExpr = typeExpr(e1);
        return buildTypedExpr(e, TEForGen(tit, te1), te1.t);
    }
  }

  function getFullPath(s:String):String
  {
    return pack.concat([s]).join('.');
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
      case CTPath(['Dynamic'], null):
        return t;
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

  function getFields(t:CType):Null<{statics:Array<String>, fields:Array<String>}>
  {
    switch (t)
    {
      case CTPath(['Null'], [p]):
        return getFields(p);

      case CTPath(path, _):
        var type:Dynamic = resolveType(path.join('.')) ?? return null;
        if (Std.isOfType(type, Class)) return {statics: Type.getClassFields(type), fields: Type.getInstanceFields(type)};
        if (Std.isOfType(type, Enum)) return {statics: Type.getEnumConstructs(type), fields: []};
        switch ((cast type : ModuleDecl))
        {
          case DClass(c):
            var superFields = c.extend != null ? getFields(c.extend) : null;
            var statics:Array<String> = superFields?.statics ?? [];
            var fields:Array<String> = superFields?.fields ?? [];
            for (f in c.fields)
              f.access.contains(AStatic) ? statics.push(f.name) : fields.push(f.name);
            return {statics: statics, fields: fields};
          case DTypedef(c):
            return getFields(c.t);
          case DEnum(e):
            return {statics: [for (f in e.fields) f.name], fields: []};
          default:
        }
        return null;

      case CTAnon(fields):
        return {statics: [], fields: [for (f in fields) f.name]};

      case CTParent(t):
        return getFields(t);

      case CTOpt(t):
        return getFields(t);

      case CTNamed(_, t):
        return getFields(t);

      default:
        return null;
    }
  }

  function resolvedTypeToCType(t:Dynamic):CType
  {
    if (Std.isOfType(t, Class))
    {
      return CTPath(['Class'], [builtin(Type.getClassName(cast t))]);
    }
    else if (Std.isOfType(t, Enum))
    {
      return CTPath(['Enum'], [builtin(Type.getEnumName(cast t))]);
    }
    else
    {
      return cast t;
    }
  }

  /**
   * Returns either `Class<Dynamic>`, `Enum<Dynamic>` or `ModuleDecl`
   */
  function resolveType(path:String):Null<Dynamic>
  {
    var pathSplit:Array<String> = path.split('.');
    if (pathSplit.length == 1)
    {
      var imp:Null<CType> = imports.get(path);
      if (imp != null)
      {
        switch (imp)
        {
          case CTPath(path, null):
            var path:String = path.join('.');
            var type:Null<Dynamic> = null;
            type ??= Type.resolveClass(path);
            type ??= Type.resolveEnum(path);
            type ??= scriptedTypes.get(path);
            if (type != null) return type;

          default:
            throw 'Should not happen: ${imp}';
        }
      }

      for (pack in everythingImports)
      {
        var path:String = pack.concat([path]).join('.');
        var type:Null<Dynamic> = null;
        type ??= Type.resolveClass(path);
        type ??= Type.resolveEnum(path);
        type ??= scriptedTypes.get(path);
        if (type != null) return type;
      }
    }

    var type:Null<Dynamic> = null;
    type ??= Type.resolveClass(path);
    type ??= Type.resolveEnum(path);
    type ??= scriptedTypes.get(path);

    return type;
  }

  function typeIsValid(t:CType):Bool
  {
    switch (t)
    {
      case CTPath(path, params):
        if (resolveType(path.join('.')) == null) return false;
        for (p in (params ?? []))
          if (!typeIsValid(p)) return false;
        return true;
      case CTFun(args, ret):
        for (a in args)
          if (!typeIsValid(a)) return false;
        if (!typeIsValid(ret)) return false;
        return true;
      case CTAnon(fields):
        for (f in fields)
          if (!typeIsValid(f.t)) return false;
        return true;
      case CTParent(t):
        return typeIsValid(t);
      case CTOpt(t):
        return typeIsValid(t);
      case CTNamed(_, t):
        return typeIsValid(t);
      case CTExpr(e):
        return true;
    }
  }

  function commonType(t1:CType, t2:CType):CType
  {
    if (equalType(t1, t2)) return removeNull(t1);
    else if (isNumber(t1) && isNumber(t2)) return builtin('Float');
    else
      return builtin('Dynamic');
  }

  function isNullUnknown(t:CType):Bool
  {
    switch (t)
    {
      case CTPath(['Null'], [CTPath(['?'], null)]):
        return true;
      default:
        return false;
    }
  }

  function isNumber(t:CType):Bool
  {
    return isInt(t) || isFloat(t);
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
    var t1:CType = removeNull(t1);
    var t2:CType = removeNull(t2);
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

  function removeNull(t:CType):CType
  {
    switch (t)
    {
      case CTPath(['Null'], [p]):
        return removeNull(p);
      case CTFun(args, ret):
        var nargs:Array<CType> = [for (a in args) removeNull(a)];
        var nret:CType = removeNull(ret);
        return CTFun(nargs, nret);
      case CTAnon(fields):
        var nfields = [for (f in fields) {name: f.name, t: removeNull(f.t), meta: f.meta}];
        return CTAnon(nfields);
      case CTParent(t):
        return CTParent(removeNull(t));
      case CTOpt(t):
        return CTOpt(removeNull(t));
      case CTNamed(n, t):
        return CTNamed(n, removeNull(t));
      default:
        return t;
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

  /**
   * Throw an `ExprError`
   * @param e The expression
   * @param m The message
   */
  function error(e:Expr, msg:String):Dynamic
  {
    #if hscriptPos
    throw new ExprError(msg, e.origin, e.line, e.pmin, e.pmax, code);
    #else
    throw new ExprError(msg);
    #end
  }

  /**
   * Throw a `ModuleError`
   * @param m The message
   */
  function moduleError(m:String):Dynamic
  {
    throw new ModuleError(m, origin);
  }

  /**
   * Throw an `ExprError`
   * @param e The expression
   * @param m The message
   * @param code The code
   */
  function moduleExprError(e:Expr, m:String, code:Null<String>):Dynamic
  {
    var oldCode:Null<String> = this.code;
    this.code = code;
    error(e, m);
    this.code = oldCode;
    return null;
  }
}

class ExprError extends haxe.Exception
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

class ModuleError extends haxe.Exception
{
  public var origin(default, null):Null<String>;

  public function new(message:String, ?origin:String)
  {
    super(message);
    this.origin = origin;
  }

  override public function toString():String
  {
    return origin != null ? '${origin}: ${message}' : message;
  }
}

typedef TyperModule =
{
  var decls:Array<ModuleDecl>;
  @:optional var code:String;
  @:optional var origin:String;
};

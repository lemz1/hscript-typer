package hscript.typer;

import hscript.Expr;

typedef TypedExpr =
{
  var e:TypedExprDef;
  var t:CType;
  #if hscriptPos
  var pmin:Int;
  var pmax:Int;
  var origin:String;
  var line:Int;
  #end
}

enum TypedExprDef
{
  TEConst(c:Const);
  TEIdent(v:String);
  TEVar(n:String, ?t:CType, ?e:TypedExpr);
  TEParent(e:TypedExpr);
  TEBlock(e:Array<TypedExpr>);
  TEField(e:TypedExpr, f:String);
  TEBinop(op:String, e1:TypedExpr, e2:TypedExpr);
  TEUnop(op:String, prefix:Bool, e:TypedExpr);
  TECall(e:TypedExpr, params:Array<TypedExpr>);
  TEIf(cond:TypedExpr, e1:TypedExpr, ?e2:TypedExpr);
  TEWhile(cond:TypedExpr, e:TypedExpr);
  TEFor(v:String, it:TypedExpr, e:TypedExpr);
  TEBreak;
  TEContinue;
  TEFunction(args:Array<TypedArgument>, e:TypedExpr, ?name:String, ?ret:CType);
  TEReturn(?e:TypedExpr);
  TEArray(e:TypedExpr, index:TypedExpr);
  TEArrayDecl(e:Array<TypedExpr>);
  TENew(cl:String, params:Array<TypedExpr>);
  TEThrow(e:TypedExpr);
  TETry(e:TypedExpr, v:String, t:Null<CType>, ecatch:TypedExpr);
  TEObject(fl:Array<{name:String, e:TypedExpr}>);
  TETernary(cond:TypedExpr, e1:TypedExpr, e2:TypedExpr);
  TESwitch(e:TypedExpr, cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>, ?defaultExpr:TypedExpr);
  TEDoWhile(cond:TypedExpr, e:TypedExpr);
  TEMeta(name:String, args:Array<Expr>, e:TypedExpr);
  TECheckType(e:TypedExpr, t:CType);
  TEForGen(it:TypedExpr, e:TypedExpr);
}

typedef TypedArgument =
{
  var name:String;
  var t:CType;
  @:optional var opt:Null<Bool>;
  @:optional var value:Null<TypedExpr>;
};

enum TypedModuleDecl
{
  TDPackage(path:Array<String>);
  TDImport(path:Array<String>, ?everything:Bool, ?name:String);
  TDClass(c:TypedClassDecl);
  TDTypedef(c:TypeDecl);
  TDEnum(e:EnumDecl);
}

typedef TypedClassDecl =
{
  > ModuleType,
  var extend:Null<CType>;
  var implement:Array<CType>;
  var fields:Array<TypedFieldDecl>;
  var isExtern:Bool;
}

typedef TypedFieldDecl =
{
  var name:String;
  var meta:Metadata;
  var kind:TypedFieldKind;
  var access:Array<FieldAccess>;
}

enum TypedFieldKind
{
  TKFunction(f:TypedFunctionDecl);
  TKVar(v:TypedVarDecl);
}

typedef TypedFunctionDecl =
{
  var args:Array<TypedArgument>;
  var expr:TypedExpr;
  var ret:CType;
}

typedef TypedVarDecl =
{
  var get:Null<String>;
  var set:Null<String>;
  var expr:Null<TypedExpr>;
  var type:CType;
}

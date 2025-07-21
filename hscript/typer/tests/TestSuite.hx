package hscript.typer.tests;

import utest.Test;
import hscript.Parser;
import hscript.Interp;
import hscript.typer.Typer;
import utest.Assert;

class TestSuite extends Test
{
  public function test():Void
  {
    assertPass('var x:Int = 10;');
    assertPass('var y:Float = 3.14;');
    assertPass('var s:String = "hello";');
    assertPass('var b:Bool = true;');
    assertPass('var arr:Array<Int> = [1, 2, 3];');
    assertPass('var arr2:Array<Float> = [1.0, 2.5, 3.14];');
    assertPass('var f = function(a:Int, b:Int):Int { return a + b; };');
    assertPass('var o = { x: 1, y: 2 };');
    assertPass('var a:Int = 5; a = 10;');
    assertPass('if (true) { var x:Int = 5; } else { var x:Int = 6; }');
    assertPass('while (false) { }');
    assertPass('for (i in [1,2,3]) { var x = i; }');
    assertPass('var n:Dynamic = if (true) 1 else "no";');
    assertPass('var z:Int = 1 + 2 * 3;');
    assertPass('var p:Float = 2.0 / 3.0;');
    assertPass('var t = (function(x:Int):Int { return x * 2; })(5);');
    assertPass('var d:Array<String> = ["a", "b", "c"];');
    assertPass('var c = new Array();');
    assertPass('var nested = { a: { b: 1 } };');
    assertPass('var ternary = true ? 1 : 0;');
    assertPass('var x:Null<Int> = 5;');
    assertPass('var y = true ? null : 5.2;');
    assertPass('var type = 5 is Int;');
  }

  function assertPass(code:String):Void
  {
    try
    {
      var parser = new Parser();
      parser.allowTypes = true;
      var e = parser.parseString(code);
      var interp = new Interp();
      var typer = new Typer(interp);
      var _ = typer.type(e, code);
      Assert.pass();
    }
    catch (e:ExprError)
    {
      Assert.fail(e.toString());
    }
  }
}

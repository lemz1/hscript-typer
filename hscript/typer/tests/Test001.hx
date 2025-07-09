package hscript.typer.tests;

import utest.Test;
import hscript.Parser;
import hscript.Interp;
import hscript.typer.Typer;
import utest.Assert;

class Test001 extends Test
{
  public function test():Void
  {
    var code = "
      function add(a:Int, b:Int):Int {
        return a + b;
      }
    ";
    assertPass(code);
  }

  function assertPass(code:String)
  {
    try
    {
      var parser = new Parser();
      parser.allowTypes = true;
      var expr = parser.parseString(code);
      var interp = new Interp();
      var typer = new Typer(interp);
      var typed = typer.type(expr);
      typer.validate(typed);
      Assert.pass();
    }
    catch (e:TyperError)
    {
      Assert.fail(e.message);
    }
  }
}

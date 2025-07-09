package hscript.typer.tests;

import utest.Test;
import hscript.Parser;
import hscript.Interp;
import hscript.typer.Typer;
import utest.Assert;

class Test006 extends Test
{
  public function test():Void
  {
    var code = "
      var arr:Array<Int> = [1, 2, 3];
    ";
    assertPass(code);
  }

  function assertPass(code:String)
  {
    try
    {
      var parser = new Parser();
      parser.allowTypes = true;
      var e = parser.parseString(code);
      var interp = new Interp();
      var typer = new Typer(interp);
      var te = typer.type(e);
      typer.validate(te);
      Assert.pass();
    }
    catch (e:TyperError)
    {
      Assert.fail(e.message);
    }
  }
}

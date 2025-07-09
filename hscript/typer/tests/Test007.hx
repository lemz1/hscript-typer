package hscript.typer.tests;

import utest.Test;
import hscript.Parser;
import hscript.Interp;
import hscript.typer.Typer;
import utest.Assert;

class Test007 extends Test
{
  public function test():Void
  {
    var code = "
      var arr:Array<Int> = [1, 'a', 3];
    ";
    assertFails(code);
  }

  function assertFails(code:String)
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
      Assert.fail("Expected type error but passed.");
    }
    catch (e:TyperError)
    {
      trace(e.toString());
      Assert.pass();
    }
  }
}

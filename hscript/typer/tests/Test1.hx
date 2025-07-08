package hscript.typer.tests;

import utest.Test;
import utest.Assert;
import hscript.Interp;
import hscript.Parser;

using hscript.typer.TypedExprTools;

class Test1 extends Test
{
  public function test():Void
  {
    try
    {
      var parser = new Parser();
      parser.allowTypes = true;
      var e = parser.parseString('
      var a = [for (i in [1, 2]) i];
      ');
      var interp = new Interp();
      var typer = new Typer(interp);
      var te = typer.type(e);
      trace(te.toString(false));
      Assert.pass();
    }
    catch (e:String)
    {
      Assert.fail(e);
    }
  }
}

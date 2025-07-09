package hscript.typer.tests;

import utest.Test;
import utest.Assert;
import hscript.Interp;
import hscript.Parser;

class Test1 extends Test
{
  public function test():Void
  {
    try
    {
      var parser = new Parser();
      parser.allowTypes = true;
      var e = parser.parseString('
      var a = 50;
      var b = 30.0;
      a == b;
      ');
      var interp = new Interp();
      var typer = new Typer(interp);
      var te = typer.type(e);
      typer.validate(te);
      Assert.pass();
    }
    catch (e:String)
    {
      Assert.fail(e);
    }
  }
}

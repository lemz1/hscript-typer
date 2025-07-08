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
      var a:Float;
      a = 15;
      ');
      var interp = new Interp();
      var typer = new Typer(interp);
      typer.type(e);
      Assert.pass();
    }
    catch (e:String)
    {
      Assert.fail(e);
    }
  }
}

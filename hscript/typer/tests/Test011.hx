package hscript.typer.tests;

import utest.Test;
import hscript.Parser;
import hscript.Interp;
import hscript.typer.Typer;
import utest.Assert;

class Test011 extends Test
{
  public function test():Void
  {
    var code = "
      {
        var x:Int = 5;
        {
          var x:String = 'hello';
        }
        x = 'oops';
      }
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
      Assert.pass();
    }
  }
}

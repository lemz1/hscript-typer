package hscript.typer.tests;

import utest.Test;
import hscript.Parser;
import hscript.Interp;
import hscript.typer.Typer;
import utest.Assert;

class TestSuiteModules extends Test
{
  public function test():Void
  {
    assertPass('
    package test1;

    class MyClass 
    {
      var x:Int;

      public function new() 
      {
        this.x = 5;
        x += 5;
      }
    }
    ');
  }

  function assertPass(code:String):Void
  {
    try
    {
      var parser = new Parser();
      parser.allowTypes = true;
      var modules = parser.parseModule(code);
      var interp = new Interp();
      var typer = new Typer(interp);
      typer.typeModules([modules]);
      typer.validateModules();
      Assert.pass();
    }
    catch (e:TyperError)
    {
      Assert.fail(e.toString());
    }
  }
}

package hscript.typer.tests;

import utest.Runner;
import utest.ui.Report;

class TestRunner
{
  public static function main()
  {
    var runner = new Runner();
    runner.addCase(new Test001());
    runner.addCase(new Test002());
    runner.addCase(new Test003());
    runner.addCase(new Test004());
    runner.addCase(new Test005());
    runner.addCase(new Test006());
    runner.addCase(new Test007());
    runner.addCase(new Test008());
    runner.addCase(new Test009());
    runner.addCase(new Test010());
    runner.addCase(new Test011());
    runner.addCase(new Test012());
    runner.addCase(new Test013());
    Report.create(runner);
    runner.run();
  }
}

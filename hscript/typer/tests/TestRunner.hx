package hscript.typer.tests;

import utest.Runner;
import utest.ui.Report;

class TestRunner
{
  public static function main()
  {
    var runner = new Runner();
    runner.addCase(new TestSuite());
    Report.create(runner);
    runner.run();
  }
}

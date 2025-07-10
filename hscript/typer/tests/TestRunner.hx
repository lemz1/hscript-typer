package hscript.typer.tests;

import utest.Runner;
import utest.ui.Report;

class TestRunner
{
  public static function main()
  {
    var runner = new Runner();
    runner.addCase(new TestSuite());
    runner.addCase(new TestSuiteModules());
    Report.create(runner);
    runner.run();
  }
}

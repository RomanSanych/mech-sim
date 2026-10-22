using System;
using System.IO;
using System.Linq;
using Mono.Cecil;

class P {
  static void Main(string[] args) {
    var resolver = new DefaultAssemblyResolver();
    resolver.AddSearchDirectory(Path.GetDirectoryName(args[0]));
    var rp = new ReaderParameters { AssemblyResolver = resolver, ReadSymbols = false };
    var mod = ModuleDefinition.ReadModule(args[0], rp);
    Console.WriteLine("ASSEMBLY " + mod.Assembly.Name.Name);
    foreach (var t in mod.Types.OrderBy(x => x.FullName)) {
      Console.WriteLine("TYPE " + t.FullName);
      foreach (var m in t.Methods.Where(m => m.IsPublic || m.IsFamily)) {
        Console.WriteLine("  M " + m.FullName);
      }
      foreach (var f in t.Fields) {
        Console.WriteLine("  F " + f.FullName);
      }
      foreach (var p in t.Properties) {
        Console.WriteLine("  P " + p.FullName);
      }
    }
  }
}

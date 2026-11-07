using Autodesk.AutoCAD.Runtime;
using CadApplication = Autodesk.AutoCAD.ApplicationServices.Core.Application;
using PassAiFire.Core;

[assembly: CommandClass(typeof(PassAiFire.AutoCAD2024.Diagnostics))]

namespace PassAiFire.AutoCAD2024
{
    // Deliberately registers only read-only foundation diagnostics.
    public sealed class Diagnostics
    {
        [CommandMethod("PASSAIFIRE_ABOUT", CommandFlags.Modal)]
        public void About() => Write(FoundationInfo.About);

        [CommandMethod("PASSAIFIRE_STATUS", CommandFlags.Modal)]
        public void Status() => Write(FoundationInfo.Status(FeatureCatalog.Load()));

        private static void Write(string message)
        {
            var document = CadApplication.DocumentManager.MdiActiveDocument;
            if (document != null) document.Editor.WriteMessage("\n" + message + "\n");
        }
    }
}

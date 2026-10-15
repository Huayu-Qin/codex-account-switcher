using System.Drawing;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new DesktopFixture());
    }

    private sealed class DesktopFixture : Form
    {
        private readonly string mode = File.Exists(Path.Combine(AppContext.BaseDirectory, "mode.txt"))
            ? File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "mode.txt")) : "quit";
        private bool quitting;
        private readonly NativeWindow helper = new();

        public DesktopFixture()
        {
            Text = "Codex quit test fixture";
            ClientSize = new Size(360, 90);
            FormBorderStyle = FormBorderStyle.FixedSingle;
            StartPosition = FormStartPosition.CenterScreen;
            ShowInTaskbar = true;
            // Titled, hidden IME/OLE helper windows must not be mistaken for the tray window.
            helper.CreateHandle(new CreateParams { Caption = "Fixture input helper", Style = unchecked((int)0x84000000) });
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (!quitting)
            {
                e.Cancel = true;
                Hide();
                Record("hidden");
            }
            else Record("exited");
            base.OnFormClosing(e);
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (keyData != (Keys.Control | Keys.Q)) return base.ProcessCmdKey(ref msg, keyData);
            Record("quit-requested");
            if (mode != "cancel") QuitAsync();
            return true;
        }

        private async void QuitAsync()
        {
            if (mode == "delay") await Task.Delay(1200);
            quitting = true;
            Close();
        }

        private static void Record(string action) => File.AppendAllText(Path.Combine(AppContext.BaseDirectory, "events.txt"), action + "\n");

        protected override void Dispose(bool disposing)
        {
            if (disposing) helper.DestroyHandle();
            base.Dispose(disposing);
        }
    }
}

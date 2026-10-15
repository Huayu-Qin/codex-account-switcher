using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace CodexAccountSwitcher.Core;

internal static class DesktopQuitRequest
{
    // Codex's Windows application menu binds Ctrl+Q to Electron's quit role.
    // WM_CLOSE only hides its last window to the tray and never requests app.quit().
    internal static async Task SendAsync(IReadOnlyList<Process> processes, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        var processIds = processes.Where(process => !process.HasExited).Select(process => (uint)process.Id).ToHashSet();
        var windows = new List<IntPtr>();
        EnumWindows((window, _) =>
        {
            GetWindowThreadProcessId(window, out var pid);
            var extendedStyle = GetWindowLong(window, -20 /* GWL_EXSTYLE */);
            if (processIds.Contains(pid) && GetWindow(window, 4 /* GW_OWNER */) == IntPtr.Zero &&
                GetWindowTextLength(window) > 0 && (extendedStyle & 0x40000 /* WS_EX_APPWINDOW */) != 0 &&
                (extendedStyle & 0x80 /* WS_EX_TOOLWINDOW */) == 0)
                windows.Add(window);
            return true;
        }, IntPtr.Zero);

        // EnumWindows includes hidden tray windows; Process.MainWindowHandle does not.
        var target = windows.OrderByDescending(IsWindowVisible).FirstOrDefault();
        if (target == IntPtr.Zero || !IsWindowEnabled(target))
            throw new IOException("Codex Desktop has no available application window. Dismiss its dialog or quit it from the tray before switching.");

        ct.ThrowIfCancellationRequested();
        EnsureModifiersReleased();
        ShowWindowAsync(target, IsIconic(target) ? 9 /* SW_RESTORE */ : 5 /* SW_SHOW */);
        SetForegroundWindow(target);
        var focusWait = Stopwatch.StartNew();
        while (GetForegroundWindow() != target && focusWait.Elapsed < TimeSpan.FromSeconds(1))
            await Task.Delay(50, ct);

        ct.ThrowIfCancellationRequested();
        // Do not release the user's held modifiers or turn Ctrl+Q into a different shortcut.
        EnsureModifiersReleased();
        GetWindowThreadProcessId(target, out var targetPid);
        if (!processIds.Contains(targetPid) || GetForegroundWindow() != target || !IsWindowEnabled(target))
            throw new IOException("Could not focus Codex Desktop to request Quit. Quit it from its File or tray menu before switching.");
        Input[] inputs = [Key(0x11), Key(0x51), Key(0x51, keyUp: true), Key(0x11, keyUp: true)];
        // Submit the whole chord together, only after verifying the matched Desktop owns focus.
        var sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>());
        if (sent != inputs.Length)
        {
            var error = new Win32Exception(Marshal.GetLastWin32Error());
            if (sent > 0) SendInput(2, [Key(0x51, keyUp: true), Key(0x11, keyUp: true)], Marshal.SizeOf<Input>());
            throw new IOException("Could not send the normal Quit shortcut to Codex Desktop.", error);
        }
    }

    private static void EnsureModifiersReleased()
    {
        if (new[] { 0x10, 0x11, 0x12, 0x5B, 0x5C }.Any(key => (GetAsyncKeyState(key) & 0x8000) != 0))
            throw new IOException("Release the keyboard modifiers and try switching again, or quit Codex Desktop from its tray menu.");
    }

    private static Input Key(ushort key, bool keyUp = false) => new()
    {
        Type = 1 /* INPUT_KEYBOARD */,
        Data = new InputData { Keyboard = new KeyboardInput { VirtualKey = key, Flags = keyUp ? 2u : 0u } }
    };

    [StructLayout(LayoutKind.Sequential)]
    private struct Input { public uint Type; public InputData Data; }
    [StructLayout(LayoutKind.Explicit)]
    private struct InputData
    {
        [FieldOffset(0)] public KeyboardInput Keyboard;
        // INPUT's union must retain MOUSEINPUT's size/alignment on both x86 and x64.
        [FieldOffset(0)] public MouseInput Mouse;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput { public ushort VirtualKey, Scan; public uint Flags, Time; public UIntPtr ExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput { public int X, Y; public uint MouseData, Flags, Time; public UIntPtr ExtraInfo; }

    private delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr window, uint command);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLength(IntPtr window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowLong(IntPtr window, int index);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] private static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
}

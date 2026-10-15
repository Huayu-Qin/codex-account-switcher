using System.Diagnostics;
using CodexAccountSwitcher.Core;

internal static class DesktopCloseChecks
{
    public static async Task<int> RunAsync(string fixtureExecutable)
    {
        var root = Path.Combine(Path.GetTempPath(), "codex-desktop-close-check-" + Guid.NewGuid().ToString("N"));
        var oldExecutable = Path.Combine(root, "OpenAI.Codex_1.0.0.0_x64__fixture", "app", "ChatGPT.exe");
        var newExecutable = Path.Combine(root, "OpenAI.Codex_2.0.0.0_x64__fixture", "app", "ChatGPT.exe");
        Directory.CreateDirectory(Path.GetDirectoryName(oldExecutable)!);
        Directory.CreateDirectory(Path.GetDirectoryName(newExecutable)!);
        try
        {
            await VerifyRunningPackageIdentityAsync();
            CopyFixture(fixtureExecutable, Path.GetDirectoryName(oldExecutable)!);
            CopyFixture(fixtureExecutable, Path.GetDirectoryName(newExecutable)!);

            var installedVersion = 1;
            var discoveryCount = 0;
            var controller = new DesktopController(cancellationToken =>
            {
                cancellationToken.ThrowIfCancellationRequested();
                discoveryCount++;
                return Task.FromResult(new DesktopInstallation(installedVersion == 1 ? oldExecutable : newExecutable));
            });

            await controller.OpenAsync(CancellationToken.None);
            await WaitForWindowAsync(oldExecutable);
            await controller.CloseAsync(CancellationToken.None);
            Require(!IsRunning(oldExecutable), "The version 1 fixture should exit through its Quit shortcut.");
            Require(ReadEvents(oldExecutable).SequenceEqual(["quit-requested", "exited"]), "Quit must bypass window-close-to-tray behavior.");

            // Simulate a Store update moving ChatGPT.exe to a new versioned package directory.
            installedVersion = 2;
            await controller.OpenAsync(CancellationToken.None);
            await WaitForWindowAsync(newExecutable);

            // This fixed old path reproduces the cached-installation failure: it cannot see the new process.
            var staleController = new DesktopController(_ => Task.FromResult(new DesktopInstallation(oldExecutable)));
            await staleController.CloseAsync(CancellationToken.None);
            Require(IsRunning(newExecutable), "A stale package path must not claim the updated fixture was closed.");

            // The same long-lived controller must resolve the updated path again for the next handoff.
            await controller.CloseAsync(CancellationToken.None);
            Require(!IsRunning(newExecutable), "The refreshed package path should close the updated fixture.");
            Require(discoveryCount == 4, "Each open and close operation should discover the current package path.");

            Console.WriteLine("PASS: each open and quit rediscovers the Store path; Quit exits instead of hiding the window.");
            await VerifyTrayQuitAsync(controller, newExecutable);
            await VerifyIsolationAsync(controller, newExecutable, oldExecutable);
            await VerifyDelayedQuitAsync(controller, newExecutable);
            await VerifyCancelledQuitAsync(controller, newExecutable);
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            return 1;
        }
        finally
        {
            StopFixture(oldExecutable);
            StopFixture(newExecutable);
            SecureFiles.DeleteOwnedDirectory(Path.GetTempPath(), root);
        }
    }

    private static async Task VerifyTrayQuitAsync(DesktopController controller, string executable)
    {
        Prepare(executable);
        await controller.OpenAsync(CancellationToken.None);
        await WaitForWindowAsync(executable);
        using (var fixture = FindFixture(executable))
            Require(fixture!.CloseMainWindow(), "The fixture must accept window close.");
        await UntilAsync(() => ReadEvents(executable).Contains("hidden"));
        using (var hidden = FindFixture(executable))
            Require(hidden is not null && hidden.MainWindowHandle == IntPtr.Zero, "Window close should leave a hidden running process, reproducing #29.");
        await controller.CloseAsync(CancellationToken.None);
        Require(!IsRunning(executable), "Quit must also reach an already hidden tray window.");
        Require(ReadEvents(executable).SequenceEqual(["hidden", "quit-requested", "exited"]), "The hidden window must receive one normal Quit request.");
        Console.WriteLine("PASS: a window closed to the tray is restored and exits normally.");
    }

    private static async Task VerifyIsolationAsync(DesktopController controller, string executable, string unrelatedExecutable)
    {
        Prepare(unrelatedExecutable);
        var unrelated = new DesktopController(_ => Task.FromResult(new DesktopInstallation(unrelatedExecutable)));
        await unrelated.OpenAsync(CancellationToken.None);
        await WaitForWindowAsync(unrelatedExecutable);
        Prepare(executable);
        await controller.OpenAsync(CancellationToken.None);
        await WaitForWindowAsync(executable);
        await controller.CloseAsync(CancellationToken.None);
        Require(!IsRunning(executable), "The selected Desktop should exit.");
        Require(IsRunning(unrelatedExecutable) && ReadEvents(unrelatedExecutable).Length == 0,
            "The same-named process at a different path must receive no quit or window-close request.");
        await unrelated.CloseAsync(CancellationToken.None);
        Console.WriteLine("PASS: a same-named process at another path is untouched.");
    }

    private static async Task VerifyDelayedQuitAsync(DesktopController controller, string executable)
    {
        Prepare(executable, "delay");
        await controller.OpenAsync(CancellationToken.None);
        await WaitForWindowAsync(executable);
        var stopwatch = Stopwatch.StartNew();
        await controller.CloseAsync(CancellationToken.None);
        Require(stopwatch.Elapsed >= TimeSpan.FromSeconds(1), "Quit must wait for normal application cleanup.");
        Require(ReadEvents(executable).SequenceEqual(["quit-requested", "exited"]), "Cleanup must complete without retrying or killing the process.");
        Console.WriteLine("PASS: normal asynchronous shutdown is awaited.");
    }

    private static async Task VerifyCancelledQuitAsync(DesktopController controller, string executable)
    {
        Prepare(executable, "cancel");
        await controller.OpenAsync(CancellationToken.None);
        await WaitForWindowAsync(executable);
        using (var cancelled = new CancellationTokenSource())
        {
            cancelled.Cancel();
            try
            {
                await controller.CloseAsync(cancelled.Token);
                throw new InvalidOperationException("A cancelled handoff must stop before requesting Quit.");
            }
            catch (OperationCanceledException) { }
        }
        Require(ReadEvents(executable).Length == 0, "Pre-cancellation must not send any input.");
        try
        {
            await controller.CloseAsync(CancellationToken.None, TimeSpan.FromSeconds(1));
            throw new InvalidOperationException("Refusing Quit should time out.");
        }
        catch (TimeoutException) { }
        Require(IsRunning(executable) && ReadEvents(executable).SequenceEqual(["quit-requested"]),
            "Cancelling Quit must preserve the process and must not fall back to closing or killing it.");

        using var cancellation = new CancellationTokenSource();
        var close = controller.CloseAsync(cancellation.Token);
        await UntilAsync(() => ReadEvents(executable).Length == 2);
        cancellation.Cancel();
        try
        {
            await close;
            throw new InvalidOperationException("Cancellation while waiting for exit must stop the handoff.");
        }
        catch (OperationCanceledException) { }
        Require(IsRunning(executable) && ReadEvents(executable).All(e => e == "quit-requested"),
            "Cancelling the wait must leave the process running.");
        StopFixture(executable);
        Console.WriteLine("PASS: pre-cancellation, a refused Quit, timeout and wait cancellation preserve the running app.");
    }

    private static void Prepare(string executable, string mode = "quit")
    {
        var directory = Path.GetDirectoryName(executable)!;
        File.WriteAllText(Path.Combine(directory, "mode.txt"), mode);
        File.WriteAllText(Path.Combine(directory, "events.txt"), "");
    }

    private static string[] ReadEvents(string executable)
    {
        var path = Path.Combine(Path.GetDirectoryName(executable)!, "events.txt");
        if (!File.Exists(path)) return [];
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd().Split('\n', StringSplitOptions.RemoveEmptyEntries);
    }

    private static bool IsRunning(string executable)
    {
        using var fixture = FindFixture(executable);
        return fixture is not null;
    }

    private static async Task UntilAsync(Func<bool> condition)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        while (!condition()) await Task.Delay(50, timeout.Token);
    }

    private static void CopyFixture(string executable, string destination)
    {
        foreach (var file in Directory.EnumerateFiles(Path.GetDirectoryName(Path.GetFullPath(executable))!))
            File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), overwrite: true);
    }

    private static async Task VerifyRunningPackageIdentityAsync()
    {
        DesktopInstallation installation;
        try { installation = await DesktopController.DiscoverAsync(null); }
        catch (FileNotFoundException) { return; }
        if (installation.AppUserModelId is null) return;

        foreach (var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(installation.Executable)))
        {
            try
            {
                if (!string.Equals(process.MainModule?.FileName, installation.Executable, StringComparison.OrdinalIgnoreCase))
                    continue;

                var oldPackagePath = Path.Combine(Path.GetTempPath(), "old-store-version", Path.GetFileName(installation.Executable));
                Require(DesktopController.MatchesInstallation(process,
                    new DesktopInstallation(oldPackagePath, installation.AppUserModelId)),
                    "A running packaged Codex process should still match after its package path changes.");
                Console.WriteLine("PASS: the running packaged Codex process matched through its stable app identity after a simulated path change.");
                return;
            }
            finally { process.Dispose(); }
        }
    }

    private static async Task WaitForWindowAsync(string executable)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        while (!timeout.IsCancellationRequested)
        {
            using var fixture = FindFixture(executable);
            if (fixture is { MainWindowHandle: var handle } && handle != IntPtr.Zero) return;
            await Task.Delay(100, timeout.Token);
        }
        throw new TimeoutException("The isolated desktop fixture did not create a main window.");
    }

    private static Process? FindFixture(string executable)
    {
        foreach (var process in Process.GetProcessesByName("ChatGPT"))
        {
            try
            {
                if (!process.HasExited && string.Equals(process.MainModule?.FileName, executable, StringComparison.OrdinalIgnoreCase))
                    return process;
            }
            catch (InvalidOperationException) { }
            process.Dispose();
        }
        return null;
    }

    private static void StopFixture(string executable)
    {
        foreach (var process in Process.GetProcessesByName("ChatGPT"))
        {
            try
            {
                if (string.Equals(process.MainModule?.FileName, executable, StringComparison.OrdinalIgnoreCase) && !process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                    process.WaitForExit(5000);
                }
            }
            catch (Exception) { }
            finally { process.Dispose(); }
        }
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}

# Show-OSDAppUI — experimental WinForms preview

This feature is on a development branch only, not yet in PowerShell Gallery. The public module has no organization-specific repository URL or deployment profiles.

## First smoke test: full Windows (read-only)

Download the OSDApps artifact from the green CI run on PR #14 (do not download the 0.33.0 PowerShell Gallery module). Extract the OSDApps folder and run in Windows PowerShell 5.1:

    Import-Module 'C:\Temp\OSDApps\OSDApps.psd1' -Force
    Show-OSDAppUI -PreviewOnly

Check: window opens; six built-ins appear; checkbox selection works; Cache Management tab displays local cache if attached; custom catalog can be pasted into the URL field and refreshed. Offline-only refresh should use local cache and not contact the remote catalog.

## Second smoke test: actual WinPE (read-only first)

After OSDCloud has applied Windows but before reboot:

    powershell.exe -STA -NoProfile
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

Copy the PR artifact's OSDApps folder to the USB and import it using the correct drive letter, for example:

    Import-Module 'E:\Modules\OSDApps\OSDApps.psd1' -Force
    Show-OSDAppUI -PreviewOnly

If the read-only form works, test selecting/staging on a disposable test device with:

    Show-OSDAppUI -CatalogUri 'https://example.org/your-repository/catalog.json'

The Stage button only becomes active in WinPE with a detected offline Windows target. It requests confirmation before it invokes the existing Add-OSDApp cmdlets. Built-ins use default parameters; repository apps are staged together in one batch. All apps install later via SetupComplete.

## Limitations of this MVP

- Cache tab is READ ONLY; GUI synchronization and clearing are for later iterations.
- No presets, SUUD/MUSD/KIOSK logic, embedded repository URLs or external GUI dependencies.
- Unchecking a staged app does not remove it; staging is additive.
- Advanced Office settings, Firefox language and other custom app options still require CLI.
- Staging happens synchronously; the GUI may be temporarily unresponsive while work is in progress.
- GUI requires an STA PowerShell 5.1 session and WinPE GUI/.NET dependencies.
- Public release 0.33.0 remains unchanged.

If the form cannot open, capture the error using:

    try { Show-OSDAppUI -PreviewOnly -ErrorAction Stop }
    catch { $_ | Format-List * -Force; $_.ScriptStackTrace }

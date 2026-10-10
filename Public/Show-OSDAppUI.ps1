function Update-OSDAppUIInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [switch]$ResetSelection
    )

    # The catalog is managed exclusively through Set-OSDAppConfiguration.
    # Offline only affects lookup behavior and never changes the configuration.
    $catalog = (Get-OSDAppConfiguration).CatalogUri
    $State.RepositoryStatus.Text = if ($catalog) {
        "Repository: $($catalog.AbsoluteUri)"
    }
    else {
        'Repository: not configured (use Set-OSDAppConfiguration)'
    }
    $selectedIds = @(
        foreach ($item in @($State.Apps.Items)) {
            if ($item.Checked) { [string]$item.Tag.Id }
        }
    )
    if ($ResetSelection) { $State.InventoryLoaded = $false }
    $stagedApps = if ($State.Target) { @(Get-OSDAppUIStagedApps -WindowsPath $State.Target) } else { @() }
    $stagedIds = @($stagedApps | ForEach-Object { [string]$_.Id })

    # The repository tab contains only custom packages. Built-ins are shown
    # separately and never enter the set of changes being applied here.
    $catalogApps = @(Get-OSDApp -Offline:$State.Offline.Checked -ErrorAction Stop |
        Sort-Object DisplayName)
    foreach ($app in $stagedApps) {
        if ([string]$app.Id -notin @($catalogApps.Id)) {
            $catalogApps += [pscustomobject]@{
                Id = [string]$app.Id
                Source = [string]$app.Source
                DisplayName = if ($app.DisplayName) { [string]$app.DisplayName } else { [string]$app.Id }
                Availability = 'Staged only'
                Version = [string]$app.Version
                Architecture = [string]$app.Architecture
            }
        }
    }
    $repositoryApps = @($catalogApps | Where-Object { [string]$_.Source -eq 'Repository' } | Sort-Object DisplayName)
    $repositoryStagedIds = @($stagedApps | Where-Object { [string]$_.Source -eq 'Repository' } | ForEach-Object { [string]$_.Id })
    $State.Apps.BeginUpdate()
    try {
        $State.Apps.Items.Clear()
        foreach ($app in $repositoryApps) {
            $item = [System.Windows.Forms.ListViewItem]::new([string]$app.DisplayName)
            [void]$item.SubItems.Add([string]$app.Availability)
            [void]$item.SubItems.Add([string]$app.Version)
            [void]$item.SubItems.Add([string]$app.Architecture)
            $wasStaged = [string]$app.Id -in $repositoryStagedIds
            $checked = if ($State.InventoryLoaded) { [string]$app.Id -in $selectedIds } else { $wasStaged }
            [void]$item.SubItems.Add($(if ($wasStaged) { if ($checked) { 'Staged' } else { 'Remove' } } elseif ($checked) { 'Add' } else { '' }))
            $item.Tag = $app
            $item.Checked = $checked
            [void]$State.Apps.Items.Add($item)
        }
    }
    finally { $State.Apps.EndUpdate() }
    $State.InventoryLoaded = $true
    $State.Selection.Text = "$(@($State.Apps.CheckedItems).Count) selected | $($repositoryStagedIds.Count) repository apps staged"

    # Built-in inventory is read-only, including the exact config captured in
    # DeviceManifest.json. Never infer runtime config from vendor defaults.
    $State.BuiltInApps.BeginUpdate()
    try {
        $State.BuiltInApps.Items.Clear()
        foreach ($app in @($catalogApps | Where-Object { [string]$_.Source -eq 'BuiltIn' } | Sort-Object DisplayName)) {
            $staged = @($stagedApps | Where-Object { [string]$_.Id -eq [string]$app.Id } | Select-Object -First 1)
            $stagedEntry = if ($staged.Count -gt 0) { $staged[0] } else { $null }
            $item = [System.Windows.Forms.ListViewItem]::new([string]$app.DisplayName)
            [void]$item.SubItems.Add($(if ($stagedEntry) { 'Staged' } else { 'Not staged' }))
            [void]$item.SubItems.Add([string]$app.Availability)
            [void]$item.SubItems.Add($(if ($stagedEntry) { [string]$stagedEntry.Architecture } else { '-' }))
            $item.Tag = [pscustomobject]@{ App=$app; Staged=$stagedEntry }
            [void]$State.BuiltInApps.Items.Add($item)
        }
    }
    finally { $State.BuiltInApps.EndUpdate() }
    $State.BuiltInDetails.Text = 'Select a built-in application to inspect its staging configuration.'

    $State.Cache.BeginUpdate()
    try {
        $State.Cache.Items.Clear()
        foreach ($entry in @(Get-OSDAppCache -ErrorAction Stop)) {
            $item = [System.Windows.Forms.ListViewItem]::new([string]$entry.Id)
            [void]$item.SubItems.Add([string]$entry.Source)
            [void]$item.SubItems.Add([string]$entry.Architecture)
            [void]$item.SubItems.Add($(if ($entry.Valid) { 'Valid' } else { 'Missing/invalid' }))
            [void]$item.SubItems.Add($(if ($null -eq $entry.SizeMB) { '' } else { "$($entry.SizeMB) MB" }))
            [void]$State.Cache.Items.Add($item)
        }
    }
    finally { $State.Cache.EndUpdate() }
    $State.Status.Text = "Repository: $($repositoryApps.Count) apps | Built-in: $($State.BuiltInApps.Items.Count) apps | Cache: $($State.Cache.Items.Count) entries."
}

function Show-OSDAppUI {
    <#
    .SYNOPSIS
    WinForms MVP: app selection, SetupComplete staging and read-only cache view.
    .EXAMPLE
    Show-OSDAppUI -PreviewOnly
    .EXAMPLE
    Set-OSDAppConfiguration -CatalogUri 'https://example.org/catalog.json'
    Show-OSDAppUI
    .EXAMPLE
    Show-OSDAppUI -TestMode -Offline
    .NOTES
    TestMode permits full-Windows staging only to a dedicated TEMP directory.
    The active Windows setup and installation remain untouched.
    #>
    [CmdletBinding()]
    param(
        [string]$WindowsPath,
        [switch]$Offline,
        [switch]$PreviewOnly,
        [switch]$TestMode
    )

    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
        throw 'An STA session is required. Launch Windows PowerShell with powershell.exe -STA -NoProfile.'
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    }
    catch {
        throw "Windows Forms is not available in this WinPE image: $($_.Exception.Message)"
    }
    if ($script:OSDAppUIState) { throw 'OSDApps Manager is already open.' }

    $winPE = Test-OSDAppWinPE
    $target = $null
    $targetLabel = 'Full Windows: inspection only. Use -TestMode for safe staging.'
    if ($TestMode -and $winPE) {
        throw '-TestMode is for full Windows only; use the normal WinPE staging mode.'
    }
    if ($TestMode -and $PSBoundParameters.ContainsKey('WindowsPath')) {
        throw '-TestMode uses its own isolated TEMP target; do not specify -WindowsPath.'
    }
    if ($TestMode) {
        $target = Get-OSDAppUITestWindowsPath
        New-Item -Path $target -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $targetLabel = "Windows test mode | Isolated target: $target"
    }
    elseif ($winPE) {
        try {
            $target = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
            $targetLabel = "WinPE | Offline Windows target: $target"
        }
        catch {
            $targetLabel = "WinPE | No usable Windows target: $($_.Exception.Message)"
        }
    }

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = if ($TestMode) { 'OSDApps Manager - Staging Test Mode' } else { 'OSDApps Manager - Development Preview' }
    $form.Size = [System.Drawing.Size]::new(980, 700)
    $form.MinimumSize = [System.Drawing.Size]::new(780, 560)
    $form.StartPosition = 'CenterScreen'
    $form.AutoScaleMode = 'Dpi'
    $form.Font = [System.Drawing.Font]::new('Segoe UI', 9)

    $root = [System.Windows.Forms.TableLayoutPanel]::new()
    $root.Dock = 'Fill'
    $root.RowCount = 3
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute', 155))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent', 100))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute', 45))
    $form.Controls.Add($root)

    $header = [System.Windows.Forms.Panel]::new()
    $header.Dock = 'Fill'
    $header.BackColor = [System.Drawing.Color]::FromArgb(35,59,95)
    [void]$root.Controls.Add($header,0,0)

    $title = [System.Windows.Forms.Label]::new()
    $title.Text = 'OSDApps Manager'
    $title.Font = [System.Drawing.Font]::new('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::White
    $title.SetBounds(18,10,500,40)
    $header.Controls.Add($title)

    $description = [System.Windows.Forms.Label]::new()
    $description.Text = 'Repository staging, built-in overview and cache inventory'
    $description.ForeColor = [System.Drawing.Color]::White
    $description.SetBounds(20,54,750,24)
    $header.Controls.Add($description)

    $repositoryStatus = [System.Windows.Forms.Label]::new()
    $repositoryStatus.Text = 'Repository: loading...'
    $repositoryStatus.ForeColor = [System.Drawing.Color]::Gainsboro
    $repositoryStatus.AutoEllipsis = $true
    $repositoryStatus.SetBounds(24,96,615,26)
    $repositoryStatus.Anchor = 'Top,Left,Right'
    $header.Controls.Add($repositoryStatus)

    $offlineCheck = [System.Windows.Forms.CheckBox]::new()
    $offlineCheck.Text = 'Offline only'
    $offlineCheck.ForeColor = [System.Drawing.Color]::White
    $offlineCheck.Checked = [bool]$Offline
    $offlineCheck.SetBounds(650,96,120,26)
    $offlineCheck.Anchor = 'Top,Right'
    $header.Controls.Add($offlineCheck)

    $refresh = [System.Windows.Forms.Button]::new()
    $refresh.Text = 'Refresh'
    $refresh.SetBounds(820,94,100,29)
    $refresh.Anchor = 'Top,Right'
    $header.Controls.Add($refresh)

    $targetInfo = [System.Windows.Forms.Label]::new()
    $targetInfo.Text = $targetLabel
    $targetInfo.ForeColor = [System.Drawing.Color]::White
    $targetInfo.SetBounds(20,129,910,23)
    $header.Controls.Add($targetInfo)

    $tabs = [System.Windows.Forms.TabControl]::new()
    $tabs.Dock = 'Fill'
    [void]$root.Controls.Add($tabs,0,1)
    $appTab = [System.Windows.Forms.TabPage]::new('Repository')
    $builtInTab = [System.Windows.Forms.TabPage]::new('Built-in')
    $cacheTab = [System.Windows.Forms.TabPage]::new('Cache')
    [void]$tabs.TabPages.Add($appTab)
    [void]$tabs.TabPages.Add($builtInTab)
    [void]$tabs.TabPages.Add($cacheTab)

    # Explicit table rows prevent Dock=Fill from covering footer controls.
    $appLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $appLayout.Dock = 'Fill'
    $appLayout.RowCount = 3
    [void]$appLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute', 39))
    [void]$appLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent', 100))
    [void]$appLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute', 51))
    $appTab.Controls.Add($appLayout)

    $appInfo = [System.Windows.Forms.Label]::new()
    $appInfo.Text = 'Select repository apps for SetupComplete. Built-in apps are managed through PowerShell.'
    $appInfo.Dock = 'Fill'
    $appInfo.TextAlign = 'MiddleLeft'
    $appInfo.AutoEllipsis = $true
    [void]$appLayout.Controls.Add($appInfo,0,0)

    $appList = [System.Windows.Forms.ListView]::new()
    $appList.Dock = 'Fill'
    $appList.View = 'Details'
    $appList.CheckBoxes = $true
    $appList.FullRowSelect = $true
    $appList.GridLines = $true
    [void]$appList.Columns.Add('Application',270)
    [void]$appList.Columns.Add('Availability',145)
    [void]$appList.Columns.Add('Version',125)
    [void]$appList.Columns.Add('Architecture',115)
    [void]$appList.Columns.Add('Queue',100)
    [void]$appLayout.Controls.Add($appList,0,1)

    # A table cell owns the action button. Do not position it using an
    # absolute X coordinate plus Anchor=Right: before its parent is laid out
    # WinForms can calculate a negative right-margin and move the button
    # outside the visible tab (reported in the Windows 11 GUI smoke test).
    $appActions = [System.Windows.Forms.TableLayoutPanel]::new()
    $appActions.Dock = 'Fill'
    $appActions.RowCount = 1
    $appActions.ColumnCount = 2
    $appActions.Padding = [System.Windows.Forms.Padding]::new(8,6,8,6)
    [void]$appActions.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$appActions.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent',100))
    [void]$appActions.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Absolute',206))
    [void]$appLayout.Controls.Add($appActions,0,2)

    $selection = [System.Windows.Forms.Label]::new()
    $selection.Text = '0 selected'
    $selection.Dock = 'Fill'
    $selection.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    [void]$appActions.Controls.Add($selection,0,0)

    $stage = [System.Windows.Forms.Button]::new()
    $stage.Text = 'Apply Changes'
    $stage.Dock = 'Fill'
    $stage.Margin = [System.Windows.Forms.Padding]::new(4,0,4,0)
    $stage.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $stage.BackColor = [System.Drawing.Color]::FromArgb(35,59,95)
    $stage.ForeColor = [System.Drawing.Color]::White
    $stage.Enabled = (($winPE -or $TestMode) -and $null -ne $target -and -not $PreviewOnly)
    if (-not $stage.Enabled) {
        $stage.BackColor = [System.Drawing.Color]::Gainsboro
        $stage.ForeColor = [System.Drawing.Color]::DimGray
    }
    [void]$appActions.Controls.Add($stage,1,0)

    $builtInLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $builtInLayout.Dock = 'Fill'
    $builtInLayout.RowCount = 3
    [void]$builtInLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',39))
    [void]$builtInLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$builtInLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',154))
    [void]$builtInTab.Controls.Add($builtInLayout,0,0)

    $builtInInfo = [System.Windows.Forms.Label]::new()
    $builtInInfo.Text = 'Read-only. Configure and stage built-in applications using Add-OSDApp* in PowerShell.'
    $builtInInfo.Dock = 'Fill'
    $builtInInfo.TextAlign = 'MiddleLeft'
    [void]$builtInLayout.Controls.Add($builtInInfo,0,0)

    $builtInList = [System.Windows.Forms.ListView]::new()
    $builtInList.Dock = 'Fill'
    $builtInList.View = 'Details'
    $builtInList.FullRowSelect = $true
    $builtInList.GridLines = $true
    $builtInList.MultiSelect = $false
    [void]$builtInList.Columns.Add('Application',270)
    [void]$builtInList.Columns.Add('Deployment',130)
    [void]$builtInList.Columns.Add('Cache / availability',170)
    [void]$builtInList.Columns.Add('Staged architecture',145)
    [void]$builtInLayout.Controls.Add($builtInList,0,1)

    $builtInDetails = [System.Windows.Forms.TextBox]::new()
    $builtInDetails.Multiline = $true
    $builtInDetails.ReadOnly = $true
    $builtInDetails.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $builtInDetails.Dock = 'Fill'
    $builtInDetails.BackColor = [System.Drawing.Color]::White
    $builtInDetails.Text = 'Select an app to view its staged configuration.'
    [void]$builtInLayout.Controls.Add($builtInDetails,0,2)

    $cacheLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $cacheLayout.Dock = 'Fill'
    $cacheLayout.RowCount = 2
    [void]$cacheLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute', 39))
    [void]$cacheLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent', 100))
    $cacheTab.Controls.Add($cacheLayout)

    $cacheIntro = [System.Windows.Forms.Label]::new()
    $cacheIntro.Text = 'Read-only cache inventory in this preview. Sync and cache clear are next.'
    $cacheIntro.Dock = 'Fill'
    $cacheIntro.TextAlign = 'MiddleLeft'
    [void]$cacheLayout.Controls.Add($cacheIntro,0,0)

    $cacheList = [System.Windows.Forms.ListView]::new()
    $cacheList.Dock = 'Fill'
    $cacheList.View = 'Details'
    $cacheList.GridLines = $true
    [void]$cacheList.Columns.Add('Application',270)
    [void]$cacheList.Columns.Add('Source',120)
    [void]$cacheList.Columns.Add('Architecture',120)
    [void]$cacheList.Columns.Add('Integrity',145)
    [void]$cacheList.Columns.Add('Size',105)
    [void]$cacheLayout.Controls.Add($cacheList,0,1)

    $footer = [System.Windows.Forms.Panel]::new()
    $footer.Dock = 'Fill'
    [void]$root.Controls.Add($footer,0,2)
    $status = [System.Windows.Forms.Label]::new()
    $status.Text = 'Loading...'
    $status.SetBounds(20,12,780,26)
    $status.Anchor = 'Top,Left,Right'
    $footer.Controls.Add($status)
    $close = [System.Windows.Forms.Button]::new()
    $close.Text = 'Close'
    $close.SetBounds(837,7,90,29)
    $close.Anchor = 'Top,Right'
    $footer.Controls.Add($close)

    $script:OSDAppUIState = @{
        Form=$form; Apps=$appList; Cache=$cacheList; BuiltInApps=$builtInList
        BuiltInDetails=$builtInDetails; RepositoryStatus=$repositoryStatus
        Offline=$offlineCheck; Status=$status; Target=$target
        Selection=$selection; Stage=$stage; Refresh=$refresh
        PreviewOnly=[bool]$PreviewOnly; TestMode=[bool]$TestMode; InventoryLoaded=$false
    }
    $appList.Add_ItemChecked({
        $s = $script:OSDAppUIState
        if (-not $s) { return }
        $s.Selection.Text = "$(@($s.Apps.CheckedItems).Count) selected"
        $item = $_.Item
        $stagedIds = if ($s.Target) { @(Get-OSDAppUIStagedIds -WindowsPath $s.Target) } else { @() }
        $wasStaged = [string]$item.Tag.Id -in $stagedIds
        $item.SubItems[4].Text = if ($wasStaged) {
            if ($item.Checked) { 'Staged' } else { 'Remove' }
        } elseif ($item.Checked) { 'Add' } else { '' }
    })
    $builtInList.Add_SelectedIndexChanged({
        $s = $script:OSDAppUIState
        if (-not $s -or $s.BuiltInApps.SelectedItems.Count -eq 0) { return }
        $entry = $s.BuiltInApps.SelectedItems[0].Tag
        $s.BuiltInDetails.Text = Format-OSDAppUIBuiltInDetails -Application $entry.App -StagedApplication $entry.Staged
    })
    $refresh.Add_Click({
        $s = $script:OSDAppUIState
        if (-not $s) { return }
        $s.Status.Text = 'Refreshing...'
        $s.Form.Refresh()
        try { Update-OSDAppUIInventory -State $s -ResetSelection }
        catch {
            $s.Status.Text = "Refresh failed: $($_.Exception.Message)"
            [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'OSDApps - Refresh','OK','Error')
        }
    })
    $stage.Add_Click({
        $s = $script:OSDAppUIState
        if (-not $s -or $s.PreviewOnly) { return }

        $items = @(foreach ($item in @($s.Apps.CheckedItems)) { $item.Tag })
        $existing = @(Get-OSDAppUIStagedApps -WindowsPath $s.Target | Where-Object { [string]$_.Source -eq 'Repository' } | ForEach-Object { [string]$_.Id })
        $selectedIds = @($items | ForEach-Object { [string]$_.Id })
        $toAdd = @($items | Where-Object { [string]$_.Id -notin $existing })
        $toRemove = @($existing | Where-Object { $_ -notin $selectedIds })

        if ($toAdd.Count -eq 0 -and $toRemove.Count -eq 0) {
            $s.Status.Text = 'No changes to the staging queue.'
            return
        }

        $message = @(
            "Apply changes to $($s.Target)?"
            ""
            "Add: $($toAdd.Count)"
            "Remove: $($toRemove.Count)"
        ) -join [Environment]::NewLine
        if ($toRemove.Count -gt 0) {
            $message += [Environment]::NewLine + 'Unstaging removes only staged files and queue entries; USB cache is preserved.'
        }
        if ($s.TestMode) {
            $message += [Environment]::NewLine + 'TEST MODE: The real Windows installation is unaffected.'
        }
        $answer = [System.Windows.Forms.MessageBox]::Show($message,'Confirm queue changes','YesNo','Question')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $s.Stage.Enabled = $false
        $s.Refresh.Enabled = $false
        $s.Status.Text = 'Applying changes; please wait...'
        $s.Form.Refresh()
        try {
            $result = Invoke-OSDAppUIApplyChanges -Applications $items -WindowsPath $s.Target -Offline:$s.Offline.Checked -TestMode:$s.TestMode -RepositoryOnly -ErrorAction Stop
            $s.Status.Text = "Applied: $(@($result.Added).Count) added, $(@($result.Removed).Count) removed, $(@($result.Remaining).Count) staged."
            [void][System.Windows.Forms.MessageBox]::Show($s.Status.Text,'OSDApps - Queue updated','OK','Information')
            Update-OSDAppUIInventory -State $s -ResetSelection
        }
        catch {
            $s.Status.Text = "Apply failed: $($_.Exception.Message)"
            [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'OSDApps - Apply failed','OK','Error')
        }
        finally {
            $s.Refresh.Enabled = $true
            $s.Stage.Enabled = ($null -ne $s.Target -and -not $s.PreviewOnly)
        }
    })
    $close.Add_Click({ $script:OSDAppUIState.Form.Close() })

    try {
        try { Update-OSDAppUIInventory -State $script:OSDAppUIState }
        catch {
            $script:OSDAppUIState.Status.Text = "Load failed: $($_.Exception.Message)"
            Write-Warning "OSDApps UI: $($_.Exception.Message)"
        }
        [void]$form.ShowDialog()
    }
    finally {
        $script:OSDAppUIState = $null
        $form.Dispose()
    }
}

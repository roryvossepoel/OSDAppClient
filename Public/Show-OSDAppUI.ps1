function Update-OSDAppUIInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    $catalog = $null
    $inputUri = $State.Url.Text.Trim()
    if (-not $State.Offline.Checked -and $inputUri) {
        try { $catalog = [uri]$inputUri } catch { throw 'Invalid repository catalog URL.' }
        if (-not $catalog.IsAbsoluteUri -or $catalog.Scheme -notin @('http','https')) {
            throw 'Catalog URL must start with http:// or https://.'
        }
    }
    Set-OSDAppConfiguration -CatalogUri $catalog
    $selectedIds = @(
        foreach ($item in @($State.Apps.Items)) {
            if ($item.Checked) { [string]$item.Tag.Id }
        }
    )
    $stagedIds = if ($State.Target) { @(Get-OSDAppUIStagedIds -WindowsPath $State.Target) } else { @() }

    # Get-OSDApp remains the one source of truth, including custom repositories.
    $catalogApps = @(Get-OSDApp -ErrorAction Stop |
        Sort-Object @{Expression={ if ($_.Source -eq 'BuiltIn') { 0 } else { 1 } }}, DisplayName)
    $State.Apps.BeginUpdate()
    try {
        $State.Apps.Items.Clear()
        foreach ($app in $catalogApps) {
            $item = [System.Windows.Forms.ListViewItem]::new([string]$app.DisplayName)
            [void]$item.SubItems.Add([string]$app.Source)
            [void]$item.SubItems.Add([string]$app.Availability)
            [void]$item.SubItems.Add([string]$app.Version)
            $wasStaged = [string]$app.Id -in $stagedIds
            [void]$item.SubItems.Add($(if ($wasStaged) { 'Staged' } else { '' }))
            $item.Tag = $app
            $item.Checked = ($wasStaged -or [string]$app.Id -in $selectedIds)
            [void]$State.Apps.Items.Add($item)
        }
    }
    finally { $State.Apps.EndUpdate() }

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
    $State.Status.Text = "Loaded $($catalogApps.Count) applications and $($State.Cache.Items.Count) cache entries."
}

function Show-OSDAppUI {
    <#
    .SYNOPSIS
    WinForms MVP: app selection, SetupComplete staging and read-only cache view.
    .EXAMPLE
    Show-OSDAppUI -PreviewOnly
    .EXAMPLE
    Show-OSDAppUI -CatalogUri 'https://example.org/catalog.json'
    #>
    [CmdletBinding()]
    param(
        [uri]$CatalogUri,
        [string]$WindowsPath,
        [switch]$Offline,
        [switch]$PreviewOnly
    )

    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
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

    $originalCatalog = (Get-OSDAppConfiguration).CatalogUri
    $initialCatalog = if ($PSBoundParameters.ContainsKey('CatalogUri')) { $CatalogUri } else { $originalCatalog }
    $winPE = Test-OSDAppWinPE
    $target = $null
    $targetLabel = 'Full Windows: inspection only'
    if ($winPE) {
        try {
            $target = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
            $targetLabel = "WinPE | Offline Windows target: $target"
        }
        catch {
            $targetLabel = "WinPE | No usable Windows target: $($_.Exception.Message)"
        }
    }

    $form = [Windows.Forms.Form]::new()
    $form.Text = 'OSDApps Manager - Development Preview'
    $form.Size = [Drawing.Size]::new(980, 700)
    $form.MinimumSize = [Drawing.Size]::new(780, 560)
    $form.StartPosition = 'CenterScreen'
    $form.AutoScaleMode = 'Dpi'
    $form.Font = [Drawing.Font]::new('Segoe UI', 9)

    $root = [Windows.Forms.TableLayoutPanel]::new()
    $root.Dock = 'Fill'
    $root.RowCount = 3
    [void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 155))
    [void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent', 100))
    [void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 45))
    $form.Controls.Add($root)

    $header = [Windows.Forms.Panel]::new()
    $header.Dock = 'Fill'
    $header.BackColor = [Drawing.Color]::FromArgb(35,59,95)
    [void]$root.Controls.Add($header,0,0)

    $title = [Windows.Forms.Label]::new()
    $title.Text = 'OSDApps Manager'
    $title.Font = [Drawing.Font]::new('Segoe UI', 17, [Drawing.FontStyle]::Bold)
    $title.ForeColor = [Drawing.Color]::White
    $title.SetBounds(18,10,500,40)
    $header.Controls.Add($title)

    $description = [Windows.Forms.Label]::new()
    $description.Text = 'Application deployment and cache management - first preview'
    $description.ForeColor = [Drawing.Color]::White
    $description.SetBounds(20,54,750,24)
    $header.Controls.Add($description)

    $url = [Windows.Forms.TextBox]::new()
    $url.Text = if ($initialCatalog) { [string]$initialCatalog.AbsoluteUri } else { '' }
    $url.SetBounds(20,96,625,26)
    $url.Anchor = 'Top,Left,Right'
    $header.Controls.Add($url)

    $offlineCheck = [Windows.Forms.CheckBox]::new()
    $offlineCheck.Text = 'Offline only'
    $offlineCheck.ForeColor = [Drawing.Color]::White
    $offlineCheck.Checked = [bool]$Offline
    $offlineCheck.SetBounds(650,96,120,26)
    $offlineCheck.Anchor = 'Top,Right'
    $header.Controls.Add($offlineCheck)

    $refresh = [Windows.Forms.Button]::new()
    $refresh.Text = 'Refresh'
    $refresh.SetBounds(820,94,100,29)
    $refresh.Anchor = 'Top,Right'
    $header.Controls.Add($refresh)

    $targetInfo = [Windows.Forms.Label]::new()
    $targetInfo.Text = $targetLabel
    $targetInfo.ForeColor = [Drawing.Color]::White
    $targetInfo.SetBounds(20,129,910,23)
    $header.Controls.Add($targetInfo)

    $tabs = [Windows.Forms.TabControl]::new()
    $tabs.Dock = 'Fill'
    [void]$root.Controls.Add($tabs,0,1)
    $appTab = [Windows.Forms.TabPage]::new('Install Applications')
    $cacheTab = [Windows.Forms.TabPage]::new('Cache Management')
    [void]$tabs.TabPages.Add($appTab)
    [void]$tabs.TabPages.Add($cacheTab)

    $appInfo = [Windows.Forms.Label]::new()
    $appInfo.Text = 'Select apps to STAGE for SetupComplete. Built-ins use defaults. Unchecking does not remove existing entries.'
    $appInfo.Dock = 'Top'
    $appInfo.Height = 39
    $appTab.Controls.Add($appInfo)

    $appList = [Windows.Forms.ListView]::new()
    $appList.Dock = 'Fill'
    $appList.View = 'Details'
    $appList.CheckBoxes = $true
    $appList.FullRowSelect = $true
    $appList.GridLines = $true
    [void]$appList.Columns.Add('Application',270)
    [void]$appList.Columns.Add('Source',125)
    [void]$appList.Columns.Add('Availability',145)
    [void]$appList.Columns.Add('Version',125)
    [void]$appList.Columns.Add('Queue',100)

    $appActions = [Windows.Forms.Panel]::new()
    $appActions.Dock = 'Bottom'
    $appActions.Height = 51
    $appTab.Controls.Add($appActions)
    $appTab.Controls.Add($appList)
    $appList.BringToFront()

    $selection = [Windows.Forms.Label]::new()
    $selection.Text = '0 selected'
    $selection.SetBounds(12,15,420,27)
    $appActions.Controls.Add($selection)

    $stage = [Windows.Forms.Button]::new()
    $stage.Text = 'Stage selected apps'
    $stage.SetBounds(735,8,175,32)
    $stage.Anchor = 'Top,Right'
    $stage.Enabled = ($winPE -and $null -ne $target -and -not $PreviewOnly)
    $appActions.Controls.Add($stage)

    $cacheIntro = [Windows.Forms.Label]::new()
    $cacheIntro.Text = 'Read-only cache inventory in this preview. Sync and cache clear are next.'
    $cacheIntro.Dock = 'Top'
    $cacheIntro.Height = 39
    $cacheTab.Controls.Add($cacheIntro)

    $cacheList = [Windows.Forms.ListView]::new()
    $cacheList.Dock = 'Fill'
    $cacheList.View = 'Details'
    $cacheList.GridLines = $true
    [void]$cacheList.Columns.Add('Application',270)
    [void]$cacheList.Columns.Add('Source',120)
    [void]$cacheList.Columns.Add('Architecture',120)
    [void]$cacheList.Columns.Add('Integrity',145)
    [void]$cacheList.Columns.Add('Size',105)
    $cacheTab.Controls.Add($cacheList)
    $cacheList.BringToFront()

    $footer = [Windows.Forms.Panel]::new()
    $footer.Dock = 'Fill'
    [void]$root.Controls.Add($footer,0,2)
    $status = [Windows.Forms.Label]::new()
    $status.Text = 'Loading...'
    $status.SetBounds(20,12,780,26)
    $status.Anchor = 'Top,Left,Right'
    $footer.Controls.Add($status)
    $close = [Windows.Forms.Button]::new()
    $close.Text = 'Close'
    $close.SetBounds(837,7,90,29)
    $close.Anchor = 'Top,Right'
    $footer.Controls.Add($close)

    $script:OSDAppUIState = @{
        Form=$form; Apps=$appList; Cache=$cacheList; Url=$url
        Offline=$offlineCheck; Status=$status; Target=$target
        Selection=$selection; Stage=$stage; Refresh=$refresh
        PreviewOnly=[bool]$PreviewOnly
    }
    $appList.Add_ItemChecked({
        $s = $script:OSDAppUIState
        if ($s) { $s.Selection.Text = "$(@($s.Apps.CheckedItems).Count) selected" }
    })
    $refresh.Add_Click({
        $s = $script:OSDAppUIState
        if (-not $s) { return }
        $s.Status.Text = 'Refreshing...'
        $s.Form.Refresh()
        try { Update-OSDAppUIInventory -State $s }
        catch {
            $s.Status.Text = "Refresh failed: $($_.Exception.Message)"
            [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'OSDApps - Refresh','OK','Error')
        }
    })
    $stage.Add_Click({
        $s = $script:OSDAppUIState
        if (-not $s -or $s.PreviewOnly) { return }
        $items = @(foreach ($item in @($s.Apps.CheckedItems)) { $item.Tag })
        if ($items.Count -eq 0) {
            [void][Windows.Forms.MessageBox]::Show('Select at least one app.','OSDApps','OK','Information')
            return
        }
        $confirmation = [Windows.Forms.MessageBox]::Show(
            "Stage $($items.Count) app(s) on $($s.Target)? Built-in defaults apply. Previous staged apps will remain.",
            'Confirm staging','YesNo','Question'
        )
        if ($confirmation -ne [Windows.Forms.DialogResult]::Yes) { return }
        $s.Stage.Enabled = $false
        $s.Refresh.Enabled = $false
        $s.Status.Text = 'Staging selected applications; please wait...'
        $s.Form.Refresh()
        try {
            $result = Invoke-OSDAppUIStage -Applications $items -WindowsPath $s.Target -Offline:$s.Offline.Checked
            $s.Status.Text = "Staged $($items.Count) applications for SetupComplete."
            [void][Windows.Forms.MessageBox]::Show('Applications were staged, not yet installed.','OSDApps','OK','Information')
            Update-OSDAppUIInventory -State $s
        }
        catch {
            $s.Status.Text = "Stage failed: $($_.Exception.Message)"
            [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'OSDApps - Stage failed','OK','Error')
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
        Set-OSDAppConfiguration -CatalogUri $originalCatalog
        $script:OSDAppUIState = $null
        $form.Dispose()
    }
}

# Oazy Cleaner engine. Windows PowerShell 5.1, ASCII only.
#
# Oazy copies this file and cleaner_catalog.json to its data folder and runs:
#   -Mode scan  -Out scan.json [-Quick]        look only, never changes anything
#   -Mode apply -Plan plan.json -Scope user|admin -Out log.json
#   -Mode undo  -Log log.json -Out result.json
# Add -Elevate to run the same command as administrator (one UAC prompt).
#
# Safety: a plan only names catalog ids, scanned startup entries and package
# names. Everything is checked again here against the catalog and its
# protected lists, every change records how to put it back, and Defender,
# Windows Update and drivers are refused outright.

param(
	[string]$Mode = "scan",
	[string]$Catalog = "",
	[string]$Plan = "",
	[string]$Log = "",
	[string]$Out = "",
	[string]$Scope = "user",
	[switch]$Elevate,
	[switch]$Quick
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
if ($Catalog -eq "") { $Catalog = Join-Path $PSScriptRoot "cleaner_catalog.json" }

$HIGH_PERF = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
$ULTIMATE = "e9a42b02-d5df-448d-aa00-03f14749eb61"
$SERVICES_ALLOWED = @("DiagTrack")
$APPROVED = "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved"

function Save-Json($obj) {
	$json = ConvertTo-Json -InputObject $obj -Depth 10 -Compress
	[IO.File]::WriteAllText($Out, $json, (New-Object Text.UTF8Encoding $false))
}

function Q($s) { return '"' + $s + '"' }

# --- Elevation -------------------------------------------------------------------

if ($Elevate) {
	$a = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", (Q $PSCommandPath), "-Mode", $Mode, "-Scope", $Scope, "-Catalog", (Q $Catalog), "-Out", (Q $Out))
	if ($Plan -ne "") { $a += @("-Plan", (Q $Plan)) }
	if ($Log -ne "") { $a += @("-Log", (Q $Log)) }
	try {
		$p = Start-Process -FilePath "powershell.exe" -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList ($a -join " ") -ErrorAction Stop
		exit $p.ExitCode
	} catch {
		Save-Json @{ ok = $false; denied = $true; error = "Windows didn't allow the change" }
		exit 1223
	}
}

# --- Helpers ---------------------------------------------------------------------

function Like-Any([string]$s, $patterns) {
	if ([string]::IsNullOrEmpty($s)) { return $false }
	foreach ($p in $patterns) { if ($s -like $p) { return $true } }
	return $false
}

function Is-Admin {
	$id = [Security.Principal.WindowsIdentity]::GetCurrent()
	return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Op-Needs-Admin($op) {
	if ($op.t -eq "service") { return $true }
	if ($op.t -eq "reg") { return ($op.path -like "HKLM:*") -or ($op.path -like "*\Policies\*") }
	return $false
}

function Op-Forbidden($op) {
	if ($op.t -eq "service") { return -not ($SERVICES_ALLOWED -contains $op.name) }
	if ($op.t -eq "reg") { return $op.path -match "Windows Defender|WindowsUpdate|WinDefend|SecurityCenter|\\Services\\|Class\\\{" }
	return $op.t -ne "power"
}

# HKCU in an elevated process can be another account (over-the-shoulder UAC),
# so admin passes write the signed-in user's hive through HKEY_USERS.
$script:Sid = ""
function Map-Path([string]$path) {
	if ($script:Sid -ne "" -and $path -like "HKCU:\*") { return "Registry::HKEY_USERS\" + $script:Sid + $path.Substring(5) }
	return $path
}

function Read-Reg([string]$path, [string]$name) {
	$r = @{ existed = $false }
	try {
		$key = Get-Item -LiteralPath $path -ErrorAction Stop
		if ($key.GetValueNames() -contains $name) {
			$r.existed = $true
			$r.kind = $key.GetValueKind($name).ToString()
			$v = $key.GetValue($name, $null, "DoNotExpandEnvironmentNames")
			if ($v -is [byte[]]) { $v = @($v | ForEach-Object { [int]$_ }) }
			$r.value = $v
		}
	} catch {}
	return $r
}

function Write-Reg([string]$path, [string]$name, [string]$kind, $value) {
	if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force -ErrorAction Stop | Out-Null }
	switch ($kind) {
		"Binary" { $value = [byte[]]@($value | ForEach-Object { [byte]$_ }) }
		"DWord" { $value = [int]$value }
		"QWord" { $value = [long]$value }
		"MultiString" { $value = [string[]]@($value) }
	}
	New-ItemProperty -LiteralPath $path -Name $name -PropertyType $kind -Value $value -Force -ErrorAction Stop | Out-Null
}

function Restore-Reg([string]$path, [string]$name, $prev) {
	if ($prev.existed) { Write-Reg $path $name $prev.kind $prev.value }
	elseif (Test-Path -LiteralPath $path) { Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue }
}

function Active-Scheme {
	$o = (powercfg /getactivescheme) -join " "
	if ($o -match "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") { return $Matches[1].ToLower() }
	return ""
}

function Op-Done($op) {
	switch ($op.t) {
		"reg" {
			$r = Read-Reg (Map-Path $op.path) $op.name
			return $r.existed -and ("" + $r.value) -eq ("" + $op.value)
		}
		"service" {
			$s = Get-Service -Name $op.name -ErrorAction SilentlyContinue
			if ($null -eq $s) { return $true }
			return ("" + $s.StartType) -eq $op.start
		}
		"power" {
			$a = Active-Scheme
			return $a -eq $op.scheme -or $a -eq $ULTIMATE
		}
	}
	return $false
}

function Has-Battery {
	try { return $null -ne (Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop | Select-Object -First 1) } catch { return $false }
}

function Pretty-Package([string]$name) {
	$last = ($name -split "\.")[-1]
	return ([regex]::Replace($last, "([a-z])([A-Z0-9])", '$1 $2')).Trim()
}

function Exe-Of([string]$cmd) {
	$c = [Environment]::ExpandEnvironmentVariables($cmd).Trim()
	if ($c.StartsWith('"')) {
		$end = $c.IndexOf('"', 1)
		if ($end -gt 1) { return $c.Substring(1, $end - 1) }
	}
	if ($c -match "^(.+?\.exe)") { return $Matches[1] }
	return ($c -split " ")[0]
}

# --- Startup apps -----------------------------------------------------------------

function Startup-Locations {
	return @(
		@{ loc = "hkcu_run"; reg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"; approved = "HKCU:\$APPROVED\Run"; admin = $false },
		@{ loc = "hklm_run"; reg = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"; approved = "HKLM:\$APPROVED\Run"; admin = $true },
		@{ loc = "hklm_run32"; reg = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; approved = "HKLM:\$APPROVED\Run32"; admin = $true },
		@{ loc = "user_folder"; folder = [Environment]::GetFolderPath("Startup"); approved = "HKCU:\$APPROVED\StartupFolder"; admin = $false },
		@{ loc = "common_folder"; folder = [Environment]::GetFolderPath("CommonStartup"); approved = "HKLM:\$APPROVED\StartupFolder"; admin = $true }
	)
}

function Startup-Entries($cat) {
	$list = New-Object System.Collections.ArrayList
	$shell = $null
	foreach ($l in Startup-Locations) {
		$raw = @()
		if ($l.reg) {
			try {
				$key = Get-Item -LiteralPath $l.reg -ErrorAction Stop
				foreach ($n in $key.GetValueNames()) {
					if ($n -eq "") { continue }
					$raw += @{ key = $n; cmd = "" + $key.GetValue($n) }
				}
			} catch {}
		} elseif ($l.folder -and (Test-Path -LiteralPath $l.folder)) {
			foreach ($f in Get-ChildItem -LiteralPath $l.folder -File -Force -ErrorAction SilentlyContinue) {
				if ($f.Name -ieq "desktop.ini") { continue }
				$cmd = $f.FullName
				if ($f.Extension -ieq ".lnk") {
					try {
						if ($null -eq $shell) { $shell = New-Object -ComObject WScript.Shell }
						$t = $shell.CreateShortcut($f.FullName).TargetPath
						if ($t) { $cmd = '"' + $t + '"' }
					} catch {}
				}
				$raw += @{ key = $f.Name; cmd = $cmd }
			}
		}
		foreach ($e in $raw) {
			$exe = Exe-Of $e.cmd
			$name = [IO.Path]::GetFileNameWithoutExtension($e.key)
			if ($l.reg) { $name = $e.key }
			$publisher = ""
			try {
				if (Test-Path -LiteralPath $exe) {
					$vi = (Get-Item -LiteralPath $exe).VersionInfo
					$publisher = "" + $vi.CompanyName
					$desc = ("" + $vi.FileDescription).Trim()
					if ($desc -ne "" -and $desc.Length -le 40 -and ($name -match "^[\w\-]+\.[\w\.\-]+$" -or $name -match "^\{")) { $name = $desc }
				}
			} catch {}
			$st = Read-Reg $l.approved $e.key
			$enabled = $true
			if ($st.existed -and $st.value -is [array] -and $st.value.Count -gt 0) { $enabled = (($st.value[0] -band 1) -eq 0) }
			$file = [IO.Path]::GetFileName($exe)
			$protected = (Like-Any $e.key $cat.startup_protected) -or (Like-Any $name $cat.startup_protected) -or (Like-Any $file $cat.startup_protected) -or (Like-Any $publisher @("*Microsoft Windows*"))
			$hint = ""
			foreach ($h in $cat.startup_hints.PSObject.Properties) {
				if ($e.key -like $h.Name -or $name -like $h.Name -or $file -like $h.Name) { $hint = $h.Value; break }
			}
			[void]$list.Add(@{ loc = $l.loc; key = $e.key; name = $name; cmd = $e.cmd; exe = $exe; publisher = $publisher; enabled = $enabled; admin = $l.admin; protected = $protected; hint = $hint })
		}
	}
	return , $list
}

# --- Store apps -------------------------------------------------------------------

function Catalog-App($cat, [string]$pkg) {
	if (Like-Any $pkg $cat.protected) { return $null }
	foreach ($e in $cat.apps) { if ($pkg -like $e.id) { return $e } }
	return $null
}

function Bloat-Apps($cat) {
	$list = New-Object System.Collections.ArrayList
	$seen = @{}
	foreach ($p in (Get-AppxPackage -ErrorAction SilentlyContinue)) {
		if ($p.IsFramework -or $p.NonRemovable -or ("" + $p.SignatureKind) -eq "System") { continue }
		$e = Catalog-App $cat $p.Name
		if ($null -eq $e) { continue }
		if ($seen.ContainsKey($p.Name)) {
			[void]$seen[$p.Name].full.Add($p.PackageFullName)
			continue
		}
		$aumid = ""
		try {
			$app = (Get-AppxPackageManifest -Package $p.PackageFullName -ErrorAction Stop).Package.Applications.Application | Select-Object -First 1
			if ($app) { $aumid = $p.PackageFamilyName + "!" + $app.Id }
		} catch {}
		$name = $e.name
		if ([string]::IsNullOrEmpty($name)) { $name = Pretty-Package $p.Name }
		$full = New-Object System.Collections.ArrayList
		[void]$full.Add($p.PackageFullName)
		$row = @{ id = $e.id; pkg = $p.Name; full = $full; pfn = $p.PackageFamilyName; name = $name; desc = $e.desc; rec = [bool]$e.rec; aumid = $aumid; version = "" + $p.Version }
		$seen[$p.Name] = $row
		[void]$list.Add($row)
	}
	return , $list
}

# --- Junk files -------------------------------------------------------------------

function Junk-Roots($item) {
	$roots = New-Object System.Collections.ArrayList
	foreach ($p in $item.paths) {
		$x = [Environment]::ExpandEnvironmentVariables($p)
		foreach ($d in (Get-Item -Path $x -Force -ErrorAction SilentlyContinue)) {
			if (-not ($d -is [IO.DirectoryInfo])) { continue }
			if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
			$f = $d.FullName.TrimEnd("\")
			# Never a drive root, Windows itself or a whole profile.
			if ($f.Length -lt 8 -or $f -ieq $env:SystemRoot -or $f -ieq $env:USERPROFILE -or $f -ieq $env:LOCALAPPDATA) { continue }
			[void]$roots.Add($f)
		}
	}
	return , $roots
}

# Walks without following junctions or symlinks, so nothing outside the
# folder can ever be reached.
function Walk-Files([string]$dir, [datetime]$cutoff, $files, $dirs, [ref]$denied) {
	try { $items = (New-Object IO.DirectoryInfo $dir).GetFileSystemInfos() } catch { $denied.Value = $true; return }
	foreach ($i in $items) {
		if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
		if ($i -is [IO.DirectoryInfo]) {
			if ($i.CreationTime -lt $cutoff) { [void]$dirs.Add($i.FullName) }
			Walk-Files $i.FullName $cutoff $files $dirs $denied
			continue
		}
		$t = $i.LastWriteTime
		if ($i.CreationTime -gt $t) { $t = $i.CreationTime }
		if ($t -lt $cutoff) { [void]$files.Add($i) }
	}
}

function Junk-Busy($item) {
	if (-not $item.skip_if_running) { return "" }
	foreach ($n in $item.skip_if_running) {
		if (Get-Process -Name $n -ErrorAction SilentlyContinue) { return $n }
	}
	return ""
}

function Recycle-Size {
	$size = [long]0
	$count = 0
	try {
		$rb = (New-Object -ComObject Shell.Application).Namespace(10)
		foreach ($it in $rb.Items()) {
			$count++
			try { $size += [long]$it.ExtendedProperty("Size") } catch {}
		}
	} catch {}
	return @{ size = $size; count = $count }
}

function Junk-Measure($item) {
	if ($item.recycle) { return Recycle-Size }
	$cutoff = (Get-Date).AddHours(-[double]$item.min_age_hours)
	$files = New-Object System.Collections.ArrayList
	$dirs = New-Object System.Collections.ArrayList
	$denied = $false
	foreach ($r in (Junk-Roots $item)) { Walk-Files $r $cutoff $files $dirs ([ref]$denied) }
	$size = [long]0
	foreach ($f in $files) { $size += $f.Length }
	return @{ size = $size; count = $files.Count; denied = $denied; files = $files; dirs = $dirs }
}

# --- Scan -------------------------------------------------------------------------

function Do-Scan($cat) {
	$battery = Has-Battery
	$admin = Is-Admin
	$tweaks = New-Object System.Collections.ArrayList
	foreach ($t in $cat.tweaks) {
		$done = $true
		$needs = $false
		foreach ($op in $t.ops) {
			if (-not (Op-Done $op)) { $done = $false }
			if (Op-Needs-Admin $op) { $needs = $true }
		}
		$rec = [bool]$t.rec
		$desc = $t.desc
		if ($t.id -eq "power_plan" -and $battery) {
			$rec = $false
			$desc = "Faster, but on a laptop it costs battery life."
		}
		[void]$tweaks.Add(@{ id = $t.id; group = $t.group; icon = $t.icon; name = $t.name; desc = $desc; rec = $rec; admin = $needs; done = $done })
	}
	$junk = New-Object System.Collections.ArrayList
	if (-not $Quick) {
		foreach ($j in $cat.junk) {
			$m = Junk-Measure $j
			$size = $m.size
			if ($j.admin -and -not $admin -and $m.denied) { $size = -1 }
			[void]$junk.Add(@{ id = $j.id; icon = $j.icon; name = $j.name; desc = $j.desc; rec = [bool]$j.rec; admin = [bool]$j.admin; size = $size; count = $m.count; busy = (Junk-Busy $j) })
		}
	}
	return @{
		ok = $true
		sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
		battery = $battery
		elevated = $admin
		apps = (Bloat-Apps $cat)
		startup = (Startup-Entries $cat)
		tweaks = $tweaks
		junk = $junk
		quick = [bool]$Quick
	}
}

# --- Apply ------------------------------------------------------------------------

function New-Entry([string]$kind, [string]$id, [string]$label) {
	return @{ kind = $kind; id = $id; label = $label; ok = $false; msg = ""; undo = $null; freed = 0 }
}

function Apply-Tweak($t) {
	$e = New-Entry "tweak" $t.id $t.name
	$done = New-Object System.Collections.ArrayList
	try {
		foreach ($op in $t.ops) {
			if (Op-Forbidden $op) { throw "Refused: not on Oazy's safe list" }
		}
		foreach ($op in $t.ops) {
			switch ($op.t) {
				"reg" {
					$path = Map-Path $op.path
					$prev = Read-Reg $path $op.name
					Write-Reg $path $op.name $op.type $op.value
					[void]$done.Add(@{ t = "reg"; path = $path; name = $op.name; prev = $prev })
				}
				"service" {
					$s = Get-Service -Name $op.name -ErrorAction SilentlyContinue
					if ($null -eq $s) { continue }
					$prev = @{ start = "" + $s.StartType; running = ("" + $s.Status) -eq "Running" }
					Set-Service -Name $op.name -StartupType $op.start -ErrorAction Stop
					if ($op.start -eq "Disabled") { Stop-Service -Name $op.name -Force -ErrorAction SilentlyContinue }
					[void]$done.Add(@{ t = "service"; name = $op.name; prev = $prev })
				}
				"power" {
					$prev = Active-Scheme
					powercfg /setactive $op.scheme 2>$null | Out-Null
					if ((Active-Scheme) -ne $op.scheme) {
						# Modern PCs often hide the plan; bring it back from its template.
						powercfg -duplicatescheme $op.scheme $op.scheme 2>$null | Out-Null
						powercfg /setactive $op.scheme 2>$null | Out-Null
					}
					if ((Active-Scheme) -ne $op.scheme) { throw "This PC doesn't offer a high performance plan" }
					[void]$done.Add(@{ t = "power"; prev = $prev })
				}
			}
		}
		$e.ok = $true
	} catch {
		$e.msg = $_.Exception.Message
		# Leave nothing half done.
		Undo-Ops $done | Out-Null
		$done.Clear()
	}
	if ($done.Count -gt 0) { $e.undo = @{ ops = $done } }
	return $e
}

function Undo-Ops($ops) {
	$arr = @($ops)
	[array]::Reverse($arr)
	foreach ($op in $arr) {
		switch ($op.t) {
			"reg" { Restore-Reg $op.path $op.name $op.prev }
			"service" {
				if ($op.prev.start -ne "") { Set-Service -Name $op.name -StartupType $op.prev.start -ErrorAction Stop }
				if ($op.prev.running) { Start-Service -Name $op.name -ErrorAction SilentlyContinue }
			}
			"power" { if ($op.prev -ne "") { powercfg /setactive $op.prev 2>$null | Out-Null } }
		}
	}
}

function Apply-App($cat, [string]$pkgName) {
	$e = New-Entry "app" $pkgName $pkgName
	try {
		$entry = Catalog-App $cat $pkgName
		if ($null -eq $entry) { throw "Refused: not on Oazy's safe list" }
		$pk = @(Get-AppxPackage -Name $pkgName -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and -not $_.NonRemovable })
		if ($pk.Count -eq 0) { $e.ok = $true; $e.msg = "Already gone"; return $e }
		$name = $entry.name
		if ([string]::IsNullOrEmpty($name)) { $name = Pretty-Package $pkgName }
		$e.label = $name
		$manifests = New-Object System.Collections.ArrayList
		foreach ($p in $pk) {
			if ($p.InstallLocation) { [void]$manifests.Add((Join-Path $p.InstallLocation "AppxManifest.xml")) }
		}
		$e.undo = @{ pkg = $pkgName; pfn = $pk[0].PackageFamilyName; manifests = $manifests }
		foreach ($p in $pk) { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop }
		$e.ok = $true
	} catch {
		$e.msg = $_.Exception.Message
		# Keep the undo record only if part of it did go.
		if (@(Get-AppxPackage -Name $pkgName -ErrorAction SilentlyContinue).Count -eq $pk.Count) { $e.undo = $null }
	}
	return $e
}

function Apply-Startup($cat, $want) {
	$e = New-Entry "startup" ($want.loc + ":" + $want.key) $want.key
	try {
		$loc = Startup-Locations | Where-Object { $_.loc -eq $want.loc } | Select-Object -First 1
		if ($null -eq $loc) { throw "Unknown startup location" }
		$entry = (Startup-Entries $cat) | Where-Object { $_.loc -eq $want.loc -and $_.key -eq $want.key } | Select-Object -First 1
		if ($null -eq $entry) { throw "It's no longer set to start with Windows" }
		$e.label = $entry.name
		if ($entry.protected) { throw "Refused: Windows needs this one" }
		$path = Map-Path $loc.approved
		$prev = Read-Reg $path $want.key
		if ($want.enable) {
			$bytes = @(2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
		} else {
			$bytes = @(3, 0, 0, 0) + @([BitConverter]::GetBytes((Get-Date).ToFileTimeUtc()) | ForEach-Object { [int]$_ })
		}
		Write-Reg $path $want.key "Binary" $bytes
		$e.undo = @{ ops = @(@{ t = "reg"; path = $path; name = $want.key; prev = $prev }) }
		$e.ok = $true
	} catch {
		$e.msg = $_.Exception.Message
	}
	return $e
}

function Apply-Junk($j) {
	$e = New-Entry "junk" $j.id $j.name
	try {
		$busy = Junk-Busy $j
		if ($busy -ne "") { throw ("Skipped while " + $busy + " is open") }
		if ($j.recycle) {
			$before = (Recycle-Size).size
			Clear-RecycleBin -Force -ErrorAction SilentlyContinue
			$e.freed = [long]($before - (Recycle-Size).size)
		} else {
			$m = Junk-Measure $j
			$freed = [long]0
			foreach ($f in $m.files) {
				try {
					$len = $f.Length
					[IO.File]::SetAttributes($f.FullName, [IO.FileAttributes]::Normal)
					[IO.File]::Delete($f.FullName)
					$freed += $len
				} catch {}
			}
			# Tidy folders that are now empty, deepest first (never the roots
			# themselves; Delete refuses folders that still hold anything).
			$dirs = @($m.dirs)
			[array]::Reverse($dirs)
			foreach ($d in $dirs) {
				try { [IO.Directory]::Delete($d, $false) } catch {}
			}
			$e.freed = $freed
		}
		$e.ok = $true
		$e.msg = "Can't be undone"
	} catch {
		$e.msg = $_.Exception.Message
	}
	return $e
}

function Make-Restore-Point {
	$r = @{ tried = $true; ok = $false; msg = "" }
	$k = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
	$prev = Read-Reg $k "SystemRestorePointCreationFrequency"
	try {
		Write-Reg $k "SystemRestorePointCreationFrequency" "DWord" 0
		Checkpoint-Computer -Description "Oazy Cleaner" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
		$r.ok = $true
	} catch {
		$r.msg = "System Restore is off on this PC, so Oazy's own undo is your safety net."
	} finally {
		try { Restore-Reg $k "SystemRestorePointCreationFrequency" $prev } catch {}
	}
	return $r
}

function Do-Apply($cat) {
	$p = Get-Content -LiteralPath $Plan -Raw -Encoding UTF8 | ConvertFrom-Json
	$admin = $Scope -eq "admin"
	if ($admin) {
		if (-not (Is-Admin)) { return @{ ok = $false; error = "Not running as administrator" } }
		$script:Sid = "" + $p.sid
	}
	$entries = New-Object System.Collections.ArrayList
	$restore = @{ tried = $false; ok = $false; msg = "" }
	if ($admin -and $p.restore_point) { $restore = Make-Restore-Point }

	foreach ($id in @($p.tweaks)) {
		$t = $cat.tweaks | Where-Object { $_.id -eq $id } | Select-Object -First 1
		if ($null -eq $t) { continue }
		$needs = $false
		foreach ($op in $t.ops) { if (Op-Needs-Admin $op) { $needs = $true } }
		if ($needs -ne $admin) { continue }
		[void]$entries.Add((Apply-Tweak $t))
	}
	if (-not $admin) {
		foreach ($pkg in @($p.apps)) { if ($pkg) { [void]$entries.Add((Apply-App $cat ("" + $pkg))) } }
	}
	foreach ($s in @($p.startup)) {
		if ($null -eq $s) { continue }
		$loc = Startup-Locations | Where-Object { $_.loc -eq $s.loc } | Select-Object -First 1
		if ($null -eq $loc -or $loc.admin -ne $admin) { continue }
		[void]$entries.Add((Apply-Startup $cat $s))
	}
	foreach ($id in @($p.junk)) {
		$j = $cat.junk | Where-Object { $_.id -eq $id } | Select-Object -First 1
		if ($null -eq $j -or [bool]$j.admin -ne $admin) { continue }
		[void]$entries.Add((Apply-Junk $j))
	}
	return @{ ok = $true; scope = $Scope; run = "" + $p.run; time = (Get-Date).ToString("o"); restore = $restore; entries = $entries }
}

# --- Undo -------------------------------------------------------------------------

function Do-Undo {
	$l = Get-Content -LiteralPath $Log -Raw -Encoding UTF8 | ConvertFrom-Json
	if ($l.scope -eq "admin" -and -not (Is-Admin)) { return @{ ok = $false; error = "Not running as administrator" } }
	$results = New-Object System.Collections.ArrayList
	$arr = @($l.entries)
	[array]::Reverse($arr)
	foreach ($e in $arr) {
		if (-not $e.ok -or $null -eq $e.undo) { continue }
		$r = @{ kind = $e.kind; id = $e.id; label = $e.label; ok = $false; msg = ""; store = "" }
		try {
			if ($e.kind -eq "app") {
				$back = $false
				if (@(Get-AppxPackage -Name $e.undo.pkg -ErrorAction SilentlyContinue).Count -gt 0) { $back = $true }
				foreach ($m in @($e.undo.manifests)) {
					if ($back) { break }
					if ($m -and (Test-Path -LiteralPath $m)) {
						try { Add-AppxPackage -Register $m -DisableDevelopmentMode -ErrorAction Stop; $back = $true } catch {}
					}
				}
				if (-not $back) {
					$r.store = "ms-windows-store://pdp/?PFN=" + $e.undo.pfn
					throw "Get it back from the Microsoft Store"
				}
			} else {
				Undo-Ops @($e.undo.ops)
			}
			$r.ok = $true
		} catch {
			$r.msg = $_.Exception.Message
		}
		[void]$results.Add($r)
	}
	return @{ ok = $true; scope = "" + $l.scope; entries = $results }
}

# --- Main -------------------------------------------------------------------------

try {
	$cat = Get-Content -LiteralPath $Catalog -Raw -Encoding UTF8 | ConvertFrom-Json
	switch ($Mode) {
		"scan" { Save-Json (Do-Scan $cat) }
		"apply" { Save-Json (Do-Apply $cat) }
		"undo" { Save-Json (Do-Undo) }
		default { Save-Json @{ ok = $false; error = "Unknown mode" } }
	}
	exit 0
} catch {
	try { Save-Json @{ ok = $false; error = $_.Exception.Message } } catch {}
	exit 1
}

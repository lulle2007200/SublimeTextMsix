param(
      $build_dir = "$($BuildRoot)/build",
      $out_dir = "$($BuildRoot)/out",

      # Package name, used for package identity
      $package_name = "SublimeText",


      # Build to download, if not specifies, latest
      $build_number, 
      # Package version, if not specified, derived from previous package version and build number
      $package_version,
      $previous_package_version = "1.0.0.0",
      # Unix timestamp of previous build, used to pick relevant changes from changelog
      $previous_package_timestamp = "0",

      $channel = "Stable",

      # Either a path to a .pfx certificate or .pfx certificate as base64 and the password must be specified
      $cert_pass,
      $cert_path,
      $cert_base64,

      $public_cert_path,
      $public_cert_base64,

      $package_base_url,
      $appinstaller_base_url,

      # A variable in which to store package info
      $build_result
)

$base_url = "https://download.sublimetext.com"
$timestamp_url = "http://timestamp.sectigo.com"

$cert_cn = $null

$build_download_url = $null
$build_file_name = $null
$build_file_path = $null

$package_files = @{}
$out_files = @{}

$appinstaller_version = "1.0.0.0"

$assets_dir = "$($BuildRoot)/Resources"
$priconfig_path = "$($BuildRoot)/priconfig.xml"
$shellext_sln = "$($BuildRoot)/ShellExt/ShellExt.sln"
$shellext_dir = "$($build_dir)/ShellExt"

$manifest_template_path = "$($BuildRoot)/AppxManifest.template.xml"
$package_dir = "$($build_dir)/package"
$build_extract_dir = "$($build_dir)/sublime"
$build_default_package_extract_dir = "$($build_dir)/default_package"
$manifest_path = "$($build_dir)/AppxManifest.xml"
$pri_path = "$($build_dir)/resources.pri"
$package_path = "$($build_dir)/$($package_name).msix"
$appinstaller_path = "$($build_dir)/$($package_name).appinstaller"
$appinstaller_template_path = "$($BuildRoot)/AppInstaller.template.xml"
$full_build_changelog_path = "$($build_extract_dir)/changelog.txt"
$build_changelog = ""
$full_changelog_path = "$($BuildRoot)/changelog.txt"
$changelog = ""
$instructions_template_path = "$($BuildRoot)/install_instructions.template.xml"
$instructions = ""
$release_note_path = "$($build_dir)/$($package_name).html"

$build_results = @{}


task GetBuildNumber -If (! $build_number) {
    $version_url = "$($base_url)/latest/$($channel.ToLower())"
    $script:build_number = $(Invoke-WebRequest -Uri "$version_url").content.trim()
    $build_results["build_number"] = $build_number
}

task GetDownloadUrlAndFilename GetBuildNumber, {
    $script:build_file_name = "sublime_text_build_$($build_number)_x64.zip"
    $script:build_download_url = "$($base_url)/$($build_file_name)"
    $script:build_file_path = "$($build_dir)/$($build_file_name)"
}

task DownloadBuild -If {! $(Test-Path "$($build_file_path)" -PathType Leaf)} {
    Invoke-WebRequest -Uri "$($build_download_url)" -OutFile "$($build_file_path)"
}

task GetBuild GetDownloadUrlAndFilename, MakeBuildDir, DownloadBuild

task ExtractBuild GetBuild, {
    Expand-Archive -LiteralPath "$($build_file_path)" -DestinationPath "$($build_extract_dir)" -Force
}

task ExtractDefaultPackage ExtractBuild, {
    Expand-Archive -LiteralPath "$($build_extract_dir)/Packages/Default.sublime-package" -DestinationPath "$($build_default_package_extract_dir)" -Force
}

task RemoveUnneededFromBuild ExtractBuild, {
    Remove-Item -LiteralPath "$($build_extract_dir)/Data" -Force -Recurse
    Remove-Item -LiteralPath "$($build_extract_dir)/update_installer.exe" -Force
}

task RepackageDefaultPackage {
    Compress-Archive -Path "$($build_default_package_extract_dir)/*" -DestinationPath "$($build_extract_dir)/Packages/Default.sublime-package" -Force
}

task RemoveUpdateCommand ExtractDefaultPackage, {
    $file = "$($build_default_package_extract_dir)/Default.sublime-commands"
    $content = $(Get-Content -Path "$($file)")
    $content = $content -replace @"
{ "caption": "Help: Check for Updates", "command": "update_check", "platform": "!Linux" },
"@, ""
    Set-Content -Path "$($file)" -Value $content

    $file = "$($build_default_package_extract_dir)/Main.sublime-menu"
    $content = $(Get-Content -Path "$($file)")
    $content = $content -replace  @"
{ "command": "update_check", "caption": "Check for Updates…" },
"@, ""
    Set-Content -Path "$($file)" -Value $content
}, RepackageDefaultPackage

task PrepareBuild RemoveUpdateCommand, RemoveUnneededFromBuild

task CollectBuildFiles PrepareBuild, {
    $package_files["$($build_extract_dir)"] = "./Sublime"
}

task CollectVisualAssets {
    $package_files["$($assets_dir)/Images"] = "./Images"
}

task CollectAssets CollectVisualAssets

task CollectPackageFiles CollectBuildFiles, CollectAssets

task GetCert -If {! $cert_path} {
    requires -Variable cert_base64
    $script:cert_path = "$($build_dir)/cert.pfx"
    $content = [Convert]::FromBase64String($cert_base64)
    [IO.File]::WriteAllBytes($cert_path, $content)
}

task GetPublicCert -If { !$public_cert_path} {
    requires -Variable public_cert_base64
    $script:public_cert_path = "$($build_dir)/cert.crt"
    $content = [Convert]::FromBase64String($public_cert_base64)
    [IO.File]::WriteAllBytes($public_cert_path, $content)
}

task GetCertCN GetCert, {
    requires -Variable cert_pass
    $cert = Get-PfxCertificate -Filepath "$($cert_path)" -Password $(ConvertTo-SecureString -String "$($cert_pass)" -Force -AsPlainText) -NoPromptForPassword
    if ($cert.Subject -match 'CN=(?<RegexTest>.*?),.*') {
        if ($matches['RegexTest'] -like '*"*') {
            $script:cert_cn = ($Element.Certificate.Subject -split 'CN="(.+?)"')[1]
        }
        else {
            $script:cert_cn = $matches['RegexTest']
        }
    }
    elseif ($Cert.Subject -match '(?<=CN=).*') {
        $script:cert_cn = $matches[0]
    }
}

task GetPackageVersion -If {! $package_version} GetBuildNumber, {
    $package_version = [System.Version]::new("$($build_number.SubString(0,1)).$($build_number.SubString(1)).0.0")
    $previous_package_version = [System.Version]::new("$($previous_package_version)")
    if($package_version -le $previous_package_version){
        $package_version = [System.Version]::new($previous_package_version.Major, $previous_package_version.Minor, $previous_package_version.Build + 1, $previous_package_version.Revision)
    }
    $script:package_version = $package_version.ToString()
    $build_results["package_version"] = $script:package_version
}

task MakeManifest GetCertCN, GetPackageVersion, MakeBuildDir, {
    Copy-Item -LiteralPath "$($manifest_template_path)" -Destination "$($manifest_path)" -Force -Recurse
    $content = $(Get-Content -Path "$($manifest_path)")
    $content = $content -replace "{VERSION}","$($package_version)"
    $content = $content -replace "{CHANNEL}", "$((Get-Culture).TextInfo.ToTitleCase($channel.ToLower()))"
    $content = $content -replace "{CN}", "$($cert_cn)"
    Set-Content -Path "$($manifest_path)" -Value $content
}

task CollectManifest MakeManifest, {
    $package_files["$($manifest_path)"] = "./AppxManifest.xml"
}

task MakePri MakeManifest, {
    exec { makepri.exe new /mn "$($manifest_path)" /o /pr "$($assets_dir)" /cf "$($priconfig_path)" /of "$($pri_path)" }
}

task CollectPri MakePri, {
    $package_files["$($pri_path)"] = "./resources.pri"
}

task MakeShellExt {
    exec { msbuild "$($shellext_sln)" /t:Rebuild /p:Configuration=Release /p:Platform=x64 /p:OutDir="$($shellext_dir)/"  }
}

task CollectShellExt MakeShellExt, {
    $package_files["$($shellext_dir)/ShellExt.dll"] = "./SublimeTextShellExt.dll"
}

task PreparePackage CollectPackageFiles, CollectManifest, CollectPri, CollectShellExt, {
    foreach($item in $package_files.GetEnumerator()){
        if(Test-Path -Type Leaf "$($item.Name)"){
            New-Item -Force "$($package_dir)/$($item.Value)" -Type File
        }
        Copy-Item -Force -Path "$($item.Name)" -Destination "$($package_dir)/$($item.Value)" -Recurse
    }
}

task MakeMsixPackage PreparePackage, MakeBuildDir, {
    exec { makeappx.exe pack /o /d "$($package_dir)/" /p "$($package_path)" }
}

task MakeSignedMsixPackage -If { signtool verify /pa "$($package_path)"; !$? } MakeMsixPackage, GetCert, {
    requires -Variable cert_pass
    exec { signtool.exe sign /f "$($cert_path)" /p "$($cert_pass)" /fd "SHA256" /tr "$($timestamp_url)" /td "SHA256" "$($package_path)" }
}

task MakeBuildChangelog ExtractBuild, {
    requires -Path "$($full_build_changelog_path)"

    $old_version = [System.Version]::new("$previous_package_version")
    $version = [int]"$($old_version.Major)$($old_version.Minor)"
    $version += 1
    $xml=[system.xml.linq.xelement]::parse("<root>" + $(get-content "$($full_build_changelog_path)") + "</root>")
    $articles = $xml.descendants("article").where({[int] $($_.Element("h2").value -replace ".*?([0-9][0-9]+).*","`$1") -ge $version})
    $content = ""
    if($articles.count){
        $content += "<article><header><h1>Changelog (Sublime Text $($channel))</h1></header>`n"
        foreach ($j in $articles){$content += $j.toString()}
        $content += "</article>`n"
    }
    $script:build_changelog = $content
}

task MakeChangelog {
    $content = $(Get-Content -Path "$($full_changelog_path)")
    $changelog_content = ""
    foreach ($line in $content){
        if($line -match "^\[([0-9]+)\].*$"){
            $timestamp = $Matches[1]
            if([int]$timestamp -gt [int]$previous_package_timestamp){
                $changelog_content += "<li>$($line -replace "^\[[0-9]+\]\s*(.*)$","`$1")</li>`n"
            }
        }
    }
    $content = ""
    if ($changelog_content){
        $content += "<article><header><h1>Changelog (Sublime Text $($channel) Package)</h1></header>`n<ul>`n"
        $content += $changelog_content
        $content += "</ul></article>`n"
    }
    $script:changelog = $content
}

task MakeInstallInstructions {
    requires -Variable package_base_url
    requires -Variable appinstaller_base_url
    $content = $(Get-Content -Path "$($instructions_template_path)")
    $content = $content -replace "{APPINSTALLER_URL}","$($package_base_url)/$($package_name).appinstaller"
    $content = $content -replace "{PUBLIC_CERT_URL}","$($package_base_url)/public_cert.crt"
    $script:instructions = $content
}

task MakeReleaseNote ?MakeInstallInstructions, MakeChangelog, MakeBuildChangelog, {
    $content = "$($instructions)" + "$($changelog)" + "$($build_changelog)"
    Set-Content -Path "$($release_note_path)" -Value $content
}

task MakeAppInstaller MakeBuildDir, GetPackageVersion, GetCertCN, {
    requires -Variable appinstaller_base_url
    requires -Variable package_base_url
    Copy-Item -Path "$($appinstaller_template_path)" -Destination "$($appinstaller_path)" -Force -Recurse
    $content = $(Get-Content -Path "$($appinstaller_path)")
    $content = $content -replace "{VERSION}","$($package_version)"
    $content = $content -replace "{CN}", "$($cert_cn)"
    $content = $content -replace "{APPINSTALLER_VERSION}", "$($appinstaller_version)"
    $content = $content -replace "{APPINSTALLER_URL}", "$($appinstaller_base_url)/$($package_name).appinstaller"
    $content = $content -replace "{PACKAGE_URL}", "$($package_base_url)/$($package_name).msix"
    Set-Content -Path "$($appinstaller_path)" -Value $content
}

task MakeBuildDir -If {! $(Test-Path "$($build_dir)" -PathType Container)} {
    New-Item -Type Directory -Path "$($build_dir)"
}

task MakeOutDir -If {! $(Test-Path "$($out_dir)" -PathType Container)} {
    New-Item -Type Directory -Path "$($out_dir)"
}

task CollectReleaseNote MakeReleaseNote, {
    $out_files["$($release_note_path)"] = "./"
}

task CollectPackage MakeSignedMsixPackage, {
    $out_files["$($package_path)"] = "./"
}

task CollectAppInstaller MakeAppInstaller, {
    $out_files["$($appinstaller_path)"] = "./"
}

task CollectPublicCert GetPublicCert, {
    $out_files["$($public_cert_path)"] = "./RootCA.crt"
}

task CollectOutFiles CollectReleaseNote, ?CollectAppInstaller, CollectPackage, ?CollectPublicCert

task PrepareRelease CollectOutFiles, MakeOutDir, {
    foreach($item in $out_files.GetEnumerator()){
        Copy-Item -Force -Path "$($item.Name)" -Destination "$($out_dir)/$($item.Value)" -Recurse
    }
}

task CanUpdate GetBuildNumber, {
    $prev_ver = [System.Version]::new("$($previous_package_version)")
    $ver = [System.Version]::new("$($build_number.SubString(0,1))","$($build_number.SubString(1))",0,0)
    $can_update = $false;
    if ($ver -gt $prev_ver){
        $can_update = $true
    }
    $build_results["can_update"] = $can_update
}

Exit-Build {
    if($build_result){
        New-Variable -Name "$($build_result)" -Value $build_results -Scope Global -Force
    }
}

task Clean {
    if(Test-Path -Type Container -Path "$($out_dir)"){
        remove-item -Force -Recurse -Path "$($out_dir)"
    }
    if(Test-Path -Type Container -Path "$($build_dir)"){
        remove-item -Force -Recurse -Path "$($build_dir)"
    }
}

task . Clean, PrepareRelease
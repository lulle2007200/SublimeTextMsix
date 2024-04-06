$global:ProgressPreference = 'SilentlyContinue'

properties {
    $script:base_url = "https://download.sublimetext.com"
    $script:timestamp_url = "http://timestamp.sectigo.com"
    $script:channel = "Stable"

    $script:package_files = @{}

    $script:package_name = "SublimeText"
    $script:appinstaller_version = "1.0.0.0"
    $script:appinstaller_base_url = $null
    $script:package_base_url = $null

    $script:previous_package_version = "0.0.0.0"
    $script:previous_package_timestamp = "0"
    $script:package_version = $null

    $script:build_number = "$($build_number_override)" #sublime package build number
    $script:download_url = $null
    $script:build_file_name = $null
    $script:build_file_path = $null

    $script:temp_dir = "./build"
    $script:out_dir = "./out"
    $script:extract_dir = "$($temp_dir)/extract"
    $script:sublime_extract_dir = "$($extract_dir)/sublime"
    $script:default_package_extract_dir = "$($extract_dir)/default_package"
    $script:manifest_dir = "$($temp_dir)/manifest"
    $script:manifest_path = "$($manifest_dir)/AppxManifest.xml"
    $script:package_dir = "$($temp_dir)/package"
    $script:package_path = "$($out_dir)/$($package_name).msix"
    $script:appinstaller_dir = "$($temp_dir)/appinstaller"
    $script:appinstaller_path = "$($appinstaller_dir)/$($package_name).appinstaller"
    $script:changelog_path = "$($changelog_path_override)"

    $script:cert_dir = "$($temp_dir)/cert"
    $script:cert_base64 = $null
    $script:cert_password = $null
    $script:cert_path = $null
    $script:public_cert_base64 = $null
    $script:public_cert_path = $null
    $script:cert_cn = $null

    $script:package_changelog = ""
    $script:instructions = ""
    $script:changelog = ""
}


task default -depends RebuildWithoutReleaseNoteAndAppInstaller

task RebuildWithoutReleaseNoteAndAppInstaller -depends Clean, MakeSignedPackage, CopyPublicCert, MakeCompleteChangelog, SaveVersionString

#not 
task MakeAppInstallerAndReleaseNote -depends CopyAppInstaller, MakeReleaseNote

task Test -Depends MakeCompleteChangelog{
    echo $($changelog_path)
}

task GetBuildNumber -precondition {return ! $build_number} {
    $version_url = "$($base_url)/latest/$($channel.ToLower())"
    $script:build_number = $(Invoke-WebRequest -Uri "$version_url").content.trim()
}

task GetDownloadUrlAndFilename -depends GetBuildNumber{
    $script:build_file_name = "sublime_text_build_$($build_number)_x64.zip"
    $script:download_url = "$($base_url)/$($build_file_name)"
}

task DownloadBuild -depends GetDownloadUrlAndFilename, MakeTempDir{
    $script:build_file_path = "$($temp_dir)/$($build_file_name)"
    Invoke-WebRequest -Uri "$($download_url)" -OutFile "$($build_file_path)"
}

task ExtractBuild -depends DownloadBuild{
    Expand-Archive -LiteralPath "$($build_file_path)" -DestinationPath "$($sublime_extract_dir)" -Force
}

task ExtractDefaultPackage -depends ExtractBuild{
    Expand-Archive -LiteralPath "$($sublime_extract_dir)/Packages/Default.sublime-package" -DestinationPath "$($default_package_extract_dir)" -Force
}

task SaveVersionString -depends GetPackageVersion, MakeOutDir{
    Set-Content -Path "$($out_dir)/version.txt" -Value "$($package_version)" -NoNewline
}

task RemoveUnneededFromBuild -depends ExtractBuild{
    Remove-Item -LiteralPath "$($sublime_extract_dir)/Data" -Force -Recurse
    Remove-Item -LiteralPath "$($sublime_extract_dir)/update_installer.exe" -Force
}

#TODO: replace update command for command that checks for package updates
task RemoveUpdateCommand -depends ExtractDefaultPackage{
    $content = $(Get-Content -Path "$($default_package_extract_dir)/Default.sublime-commands")
    $content = $content -replace @"
{ "caption": "Help: Check for Updates", "command": "update_check", "platform": "!Linux" },
"@, ""
    Set-Content -Path "$($default_package_extract_dir)/Default.sublime-commands" -Value $content

    $content = $(Get-Content -Path "$($default_package_extract_dir)/Main.sublime-menu")
    $content = $content -replace  @"
{ "command": "update_check", "caption": "Check for Updates…" },
"@, ""
    Set-Content -Path "$($default_package_extract_dir)/Main.sublime-menu" -Value $content
}

task RepackageDefaultPackage -depends RemoveUpdateCommand{
    Compress-Archive -Path "$($default_package_extract_dir)/*" -DestinationPath "$($sublime_extract_dir)/Packages/Default.sublime-package" -Force
}

task PrepareBuild -depends RemoveUnneededFromBuild, RepackageDefaultPackage

task CollectBuildFiles -depends PrepareBuild{
    $package_files["$($sublime_extract_dir)"] = "./Sublime/"
}

task CollectVisualAssets{
    $package_files["$($PSScriptRoot)/Resources/Images"]="./Images"
}

task GetCertificate -precondition{return ! $cert_path} -requiredVariables cert_base64 -depends MakeCertDir{
    $script:cert_path = "$($cert_dir)/cert.pfx"
    $content = [Convert]::FromBase64String($cert_base64)
    [IO.File]::WriteAllBytes($cert_path, $content)
}

task GetPublicCertificate -precondition{return ! $public_cert_path} -requiredVariables public_cert_base64 -depends MakeCertDir{
    $script:public_cert_path = "$($cert_dir)/public_cert.crt"
    $content = [Convert]::FromBase64String($public_cert_base64)
    [IO.File]::WriteAllBytes($public_cert_path, $content)
}

task GetCertificateCN -depends GetCertificate -requiredVariables cert_password{
    $cert = Get-PfxCertificate -Filepath "$($cert_path)" -Password $(ConvertTo-SecureString -String "$($cert_password)" -Force -AsPlainText) -NoPromptForPassword
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

task GetPackageVersion -precondition {return ! $package_version} -depends GetBuildNumber {
    $package_version = [System.Version]::new("$($build_number.SubString(0,1)).$($build_number.SubString(1)).0.0")
    $previous_package_version = [System.Version]::new("$($previous_package_version)")
    if($package_version -le $previous_package_version){
        $package_version = [System.Version]::new($previous_package_version.Major, $previous_package_version.Minor, $previous_package_version.Build + 1, $previous_package_version.Revision)
    }
    $script:package_version = $package_version.ToString()
}

task PrepareManifest -depends MakeManifestDir, GetCertificateCN, GetPackageVersion{
    Copy-Item -LiteralPath "$($PSScriptRoot)/AppxManifest.template.xml" -Destination "$($manifest_path)" -Force -Recurse
    $content = $(Get-Content -Path "$($manifest_path)")
    $content = $content -replace "{VERSION}","$($package_version)"
    $content = $content -replace "{CHANNEL}", "$((Get-Culture).TextInfo.ToTitleCase($channel.ToLower()))"
    $content = $content -replace "{CN}", "$($cert_cn)"
    Set-Content -Path "$($manifest_path)" -Value $content
}

task CollectManifest -depends PrepareManifest{
    $package_files["$($manifest_path)"]="./AppxManifest.xml"
}

task CollectAssets -depends CollectVisualAssets, CollectManifest

task PreparePackage -depends CollectBuildFiles, CollectAssets, MakePri{
    foreach($item in $package_files.GetEnumerator()){
        Copy-Item -Path "$($item.Name)" -Destination "$($package_dir)/$($item.Value)" -Force -Recurse
    }
}

#TODO: generate pri from resource file instead of directly from resource folder
task MakePri -depends MakePackageDir{
    $priconfig_path = "$($PSScriptRoot)/priconfig.xml"
    Exec {makepri.exe new /mn "$($manifest_path)" /o /pr "$($PSScriptRoot)/Resources" /cf "$($priconfig_path)" /of "$($package_dir)/resources.pri"}
}

task CopyPublicCert -depends GetPublicCertificate -precondition{return $($public_cert_path -Or $public_cert_base64)} {
    Copy-Item -Path "$($public_cert_path)" -Destination "$($out_dir)" -Force -Recurse
}

task CopyAppInstaller -depends PrepareAppInstaller -precondition{return $package_base_url -and $appinstaller_base_url} {
    Copy-Item -Path "$($appinstaller_path)" -Destination "$($out_dir)" -Force -Recurse
}

task MakeMsixPackage -depends PreparePackage, MakeOutDir{
    Exec {makeappx.exe pack /o /d "$($package_dir)/" /p "$($package_path)"}
}

task MakeSignedPackage -depends MakeMsixPackage, GetCertificate{
    Exec {signtool.exe sign /f "$($cert_path)" /p "$($cert_password)" /fd "SHA256" /tr "$($timestamp_url)" /td SHA256 "$($package_path)"}
}

task PrepareAppInstaller -depends MakeAppInstallerDir, GetCertificateCN, GetPackageVersion{
    Copy-Item -Path "$($PSScriptRoot)/AppInstaller.template.xml" -Destination "$($appinstaller_path)" -Force -Recurse
    $content = $(Get-Content -Path "$($appinstaller_path)")
    $content = $content -replace "{VERSION}","$($package_version)"
    $content = $content -replace "{CN}", "$($cert_cn)"
    $content = $content -replace "{APPINSTALLER_VERSION}", "$($appinstaller_version)"
    $content = $content -replace "{APPINSTALLER_URL}", "$($appinstaller_base_url)/$($package_name).appinstaller"
    $content = $content -replace "{PACKAGE_URL}", "$($package_base_url)/$($package_name).msix"
    Set-Content -Path "$($appinstaller_path)" -Value $content
}

task MakeInstallInstructions -precondition{return $package_base_url -and $appinstaller_base_url} {
    $content = $(Get-Content -Path "$($PSScriptRoot)/install_instructions.template.xml")
    $content = $content -replace "{APPINSTALLER_URL}","$($package_base_url)/$($package_name).appinstaller"
    $content = $content -replace "{PUBLIC_CERT_URL}","$($package_base_url)/public_cert.crt"
    $script:instructions += $content
}

task MakePackageChangelog -depends ExtractBuild, GetPackageVersion {
    $old_version = [System.Version]::new("$previous_package_version")#  4.166
    $version = [int]"$($old_version.Major)$($old_version.Minor)"
    $version += 1
    $xml=[system.xml.linq.xelement]::parse("<root>" + $(get-content "$($sublime_extract_dir)/changelog.txt") + "</root>")
    $articles = $xml.descendants("article").where({[int] $($_.Element("h2").value -replace ".*?([0-9][0-9]+).*","`$1") -ge $version})
    if($articles.count){
        $script:package_changelog += "<article><header><h1>Changelog (Sublime Text $($channel))</h1></header>`n"
        foreach ($j in $articles){$script:package_changelog += $j.toString()}
        $script:package_changelog += "</article>`n"
    }
}

task MakeChangeLog {
    $content = $(Get-Content -Path "$($PSScriptRoot)/changelog.txt")
    $changelog_content = ""
    foreach ($line in $content){
        if($line -match "^\[([0-9]+)\].*$"){
            $timestamp = $Matches[1]
            if([int]$timestamp -gt [int]$previous_package_timestamp){
                $changelog_content += "<li>$($line -replace "^\[[0-9]+\]\s*(.*)$","`$1")</li>`n"
            }
        }
    }
    if ($changelog_content){
        $script:changelog += "<article><header><h1>Changelog (Sublime Text $($channel) Package)</h1></header>`n<ul>`n"
        $script:changelog += $changelog_content
        $script:changelog += "</ul></article>`n"
    }

}

task MakeReleaseNote -depends MakeOutDir, MakeInstallInstructions, MakeCompleteChangelog{
    $content = $instructions
    $content += $(Get-Content -Path $changelog_path)
    Set-Content -LiteralPath "$($out_dir)/$($package_name)_release_note.html" -Value $content
}

task MakeCompleteChangelog -precondition{ return ! $script:changelog_path } -depends MakeOutDir, MakePackageChangeLog, MakeChangeLog{
    $content = $changelog + $package_changelog
    echo $changelog_path
    $script:changelog_path = "$($out_dir)/$($package_name)_changelog.html"
    Set-Content -LiteralPath "$($changelog_path)" -Value $content
}

task CanUpdate -requiredVariables previous_package_version -depends GetBuildNumber{
    $prev_ver = [System.Version]::new("$($previous_package_version)")
    $ver = [System.Version]::new("$($build_number.SubString(0,1))","$($build_number.SubString(1))",0,0)
    if ($ver -gt $prev_ver){
        Write-Output "New package version available"
    }else{
        Write-Error "No new package version available"
    }
}

#-------------------------------------------------------------------------------

task MakeOutDir{
    New-Item -Type Directory -Force "$($out_dir)"
}

task MakeTempDir {
    New-Item -Type Directory -Force "$($temp_dir)"
}

task MakeCertDir {
    New-Item -Type Directory -Force "$($cert_dir)"
}

task MakeManifestDir {
    New-Item -Type Directory -Force "$($manifest_dir)"
}

task MakePackageDir {
    New-Item -Type Directory -Force "$($package_dir)"
}

task MakeAppInstallerDir {
    New-Item -Type Directory -Force "$($appinstaller_dir)"
}

#-------------------------------------------------------------------------------

task CleanTemp{
    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue -Path "$($temp_dir)"
}

task CleanOut{
    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue -Path "$($out_dir)"
}

task Clean -depends CleanTemp, CleanOut
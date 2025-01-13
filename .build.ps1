param(
      $package_release_channel = "stable",
      $package_build_number,

      $public_cert_local_path,
      $private_cert_local_path,
      $private_cert_pwd,
      $public_cert_base64,
      $private_cert_base64,

      $appinstaller_base_url,
      $package_base_url,

      $previous_msix_package_build_number,
      $previous_msix_package_timestamp,


      $build_result="R"
)

$build_dir_base = "$($BuildRoot)/build"
$build_dir = "$($build_dir_base)/$($package_release_channel)"
$out_dir = "$($BuildRoot)/out/$($package_release_channel)"

$base_url = "https://download.sublimetext.com"
$timestamp_url = "http://timestamp.sectigo.com"

$manifest_template_local_path = "$($BuildRoot)/AppxManifest.template.xml"
$manifest_local_path = "$($build_dir)/AppxManifest.xml"

$priconfig_local_path = "$($BuildRoot)/priconfig.xml"
$pri_local_path = "$($build_dir)/resources.pri"
$assets_dir = "$($BuildRoot)/Resources"

$msix_package_dir = "$($build_dir)/msix_package"
$msix_package_name = "SublimeText_$($package_release_channel)_x64"
$msix_package = "$($build_dir)/$($msix_package_name).msix"
$msix_package_files = @{}

$appinstaller_template_local_path = "$($BuildRoot)/AppInstaller.template.xml"
$appinstaller_local_path = "$($build_dir)/$($msix_package_name).appinstaller"
$appinstaller_version = "1.0.0.0"
$changelog_local_path = "$($build_dir)/changelog.xml"
$release_note_local_path = "$($build_dir)/release_note.xml"

$instructions_template_local_path = "$($BuildRoot)/install_instructions.template.xml"
$full_changelog_local_path = "$($BuildRoot)/changelog.txt"

$shellext_sln_local_path = "$($BuildRoot)/ShellExt/ShellExt.sln"
$shellext_dir = "$($build_dir_base)/ShellExt"

$out_files = @{}
$build_results = @{}
$build_results["out"] = "$($out_dir)"


task GetPackageBuildNumber1 -If {! $package_build_number} {
    $version_url = "$($base_url)/latest/$($package_release_channel.ToLower())"
    $script:package_build_number = $(Invoke-WebRequest -Uri "$version_url").content.Trim()
}

task GetPackageBuildNumber -Jobs GetPackageBuildNumber1, {
    $script:build_results["package_build_number"] = $script:package_build_number
}

task GetDownloadUrl GetPackageBuildNumber, {
    $script:package_file_name = "sublime_text_build_$($package_build_number)_x64.zip"
    $script:package_download_url = "$($base_url)/$($package_file_name)"
    $script:package_local_path = "$($build_dir)/$($package_file_name)"
}

task DownloadPackage -Jobs GetDownloadUrl, MakeBuildDir, {
    if(! (Test-Path -Path "$($package_local_path)")){
        Invoke-WebRequest -Uri "$($package_download_url)" -OutFile "$($package_local_path)"
    }
}

task ExtractPackage -Jobs DownloadPackage, {
    $script:package_extract_dir = "$($build_dir)/$($package_file_name.split('.')[0])"
    Expand-Archive -LiteralPath "$($package_local_path)" -DestinationPath "$($package_extract_dir)" -Force
}

# TODO 
task MakeMsixUtilPlugin

task AddMsixUtilPlugin -Jobs MakeMsixUtilPlugin, {
    Compress-Archive -Path "$($BuildRoot)/MsixUtilPlugin/*" -DestinationPath "$($package_extract_dir)/Packages/MSIX_util.sublime-package" -Force
}

task MakeShellExt {
    exec { msbuild "$($shellext_sln_local_path)" /t:Build /restore /p:RestorePackagesConfig=true /p:Configuration=Release /p:Platform=x64  /p:OutDir="$($shellext_dir)/" }
}

task DeleteUnneededFromPackage {
    Remove-Item -Recurse -Path "$($package_extract_dir)/Data" -Force
    Remove-Item -Path "$($package_extract_dir)/update_installer.exe" -Force
}

# TODO prepare sublime package files for packaging
task PreparePackage ExtractPackage, DeleteUnneededFromPackage, AddMsixUtilPlugin


# Certificates
task GetPublicCert -If {! (Test-Path -Path "$($public_cert_local_path)" -Type Leaf)} {
    requires -Variable public_cert_base64
    $script:public_cert_local_path = "$($build_dir)/public.crt"
    $content = [Convert]::FromBase64String($public_cert_base64)
    [IO.File]::WriteAllBytes($public_cert_local_path, $content)
}

task GetPrivateCertFromVar -If{! (Test-Path -Path "$($private_cert_local_path)" -Type Leaf)} {
    requires -Variable private_cert_base64
    $script:private_cert_local_path = "$($build_dir)/private.pfx"
    $content = [Convert]::FromBase64String($private_cert_base64)
    [IO.File]::WriteAllBytes($private_cert_local_path, $content)
}

task GetPrivateCert -Jobs GetPrivateCertFromVar, {
    requires -Variable private_cert_pwd
}

task GetPrivateCertCN -Jobs GetPrivateCert, {
    $cert = Get-PfxCertificate -FilePath "$($private_cert_local_path)" -Password $(ConvertTo-SecureString -String "$($private_cert_pwd)" -Force -AsPlainText) -NoPromptForPassword
    if ($cert.Subject -match 'CN=(?<RegexTest>.*?),.*') {
        if ($matches['RegexTest'] -like '*"*') {
            $script:private_cert_cn = ($Element.Certificate.Subject -split 'CN="(.+?)"')[1]
        }
        else {
            $script:private_cert_cn = $matches['RegexTest']
        }
    }
    elseif ($Cert.Subject -match '(?<=CN=).*') {
        $script:private_cert_cn = $matches[0]
    }
}

# prepare msix package
task GetPreviousMsixPackageBuildNumber -If {! $previous_msix_package_build_number} {
    if(Test-Path -Type Leaf -Path "$($build_dir)/prev_version.txt"){
        $content = Get-Content -Path "$($build_dir)/prev_version.txt" -TotalCount 2
        $script:previous_msix_package_build_number = $content | Select-Object -Index 0
        $script:previous_msix_package_timestamp = $content | Select-Object -Index 1
    }elseif(Test-Path -Type Leaf -Path "$($BuildRoot)/prev_version.txt"){
        $content = Get-Content -Path "$($BuildRoot)/prev_version.txt" -TotalCount 2
        $script:previous_msix_package_build_number = $content | Select-Object -Index 0
        $script:previous_msix_package_timestamp = $content | Select-Object -Index 1
    }else{
        $script:previous_msix_package_build_number = "0.0.0.0"
        $script:previous_msix_package_timestamp = "0"
    }
}

task WriteMsixPackageBuildNumber {
    Set-Content -Path "$($build_dir)/prev_version.txt" -Value "$($msix_package_build_number)`n$([DateTimeOffset]::Now.ToUnixTimeSeconds().ToString())"
}

task GetMsixPackageBuildNumber -Jobs GetPreviousMsixPackageBuildNumber, GetPackageBuildNumber, {
    $msix_package_version = [System.Version]::new("$($package_build_number.SubString(0,1)).$($package_build_number.SubString(1)).0.0")
    $previous_msix_package_version = [System.Version]::new("$($previous_msix_package_build_number)")
    if($msix_package_version -le $previous_msix_package_version){
        $msix_package_version = [System.Version]::new($previous_msix_package_version.Major, $previous_msix_package_version.Minor, $previous_msix_package_version.Build + 1, $previous_msix_package_version.Revision)
    }
    $script:msix_package_build_number = $msix_package_version.ToString()
    $script:build_results["new_msix_build_number"] = $script:msix_package_build_number
}

task MakeManifest -Jobs GetPrivateCertCN, GetMsixPackageBuildNumber, MakeBuildDir, {
    Copy-Item -LiteralPath "$($manifest_template_local_path)" -Destination "$($manifest_local_path)" -Force -Recurse
    $content = $(Get-Content -Path "$($manifest_local_path)")
    $content = $content -replace "{VERSION}","$($msix_package_build_number)"
    $content = $content -replace "{CHANNEL}","$((Get-Culture).TextInfo.ToTitleCase($package_release_channel.ToLower()))"
    $content = $content -replace "{CN}","$($private_cert_cn)"
    Set-Content -Path "$($manifest_local_path)" -Value $content
}


task CollectPackageContent -Jobs PreparePackage, {
    $msix_package_files["$($package_extract_dir)"] = "./Sublime"
}

task CollectResources {
    $msix_package_files["$($assets_dir)/Images"] = "./Images"
}

task CollectShellExt -Jobs MakeShellExt, {
    $msix_package_files["$($shellext_dir)/ShellExt.dll"] = "./SublimeTextShellExt.dll"
}

task CollectMsixPackageContent -Jobs CollectPackageContent, CollectResources, CollectShellExt

task CollectMsixManifest -Jobs MakeManifest, {
    $msix_package_files["$($manifest_local_path)"] = "./AppxManifest.xml"
}

task MakePri -Jobs MakeManifest, {
    exec { makepri.exe new /mn "$($manifest_local_path)" /o /pr "$($assets_dir)" /cf "$($priconfig_local_path)" /of "$($pri_local_path)"}
}

task CollectPri -Jobs MakePri, {
    $msix_package_files["$($pri_local_path)"] = "./resources.pri"
}


# make msix package
task CollectMsixFiles CollectMsixManifest, CollectMsixPackageContent, CollectPri

task PrepareMsixPackage -Jobs CollectMsixFiles, {
    foreach($item in $msix_package_files.GetEnumerator()){
        if(Test-Path -Path "$($item.Name)" -Type Leaf){
            # Copy-Item fails if file and target path has directories that dont exist -> create empty target file
            New-Item -Path "$($msix_package_dir)/$($item.Value)" -Type File -Force
        }

        Copy-Item -Force -Path "$($item.Name)" -Destination "$($msix_package_dir)/$($item.Value)" -Recurse
    }
}

task MakeMsixPackage -Jobs PrepareMsixPackage, {
    exec { makeappx.exe pack /o /d "$($msix_package_dir)" /p "$($msix_package)" }
}

task MakeSignedMsixPackage -Jobs GetPrivateCert, MakeMsixPackage, WriteMsixPackageBuildNumber, {
    exec { signtool.exe sign /f "$($private_cert_local_path)" /p "$($private_cert_pwd)" /fd "SHA256" /tr "$($timestamp_url)" /td "SHA256" "$($msix_package)" }
}


task MakeAppInstallerFile -Jobs MakeBuildDir, GetMsixPackageBuildNumber, GetPrivateCertCN, {
    requires -Variable appinstaller_base_url
    requires -Variable package_base_url

    Copy-Item -Path "$($appinstaller_template_local_path)" -Destination "$($appinstaller_local_path)" -Force -Recurse
    $content = $(Get-Content -Path "$($appinstaller_local_path)")
    $content = $content -replace "{VERSION}","$($msix_package_build_number)"
    $content = $content -replace "{CN}", "$($private_cert_cn)"
    $content = $content -replace "{APPINSTALLER_VERSION}", "$($appinstaller_version)"
    $content = $content -replace "{APPINSTALLER_URL}", "$($appinstaller_base_url)/$($msix_package_name).appinstaller"
    $content = $content -replace "{PACKAGE_URL}", "$($package_base_url)/$($msix_package_name).msix"
    Set-Content -Path "$($appinstaller_local_path)" -Value $content
}

task MakeInstallInstructions {
    requires -Variable package_base_url
    requires -Variable appinstaller_base_url

    $content = $(Get-Content -Path "$($instructions_template_local_path)")
    $content = $content -replace "{APPINSTALLER_URL}","$($package_base_url)/$($msix_package_name).appinstaller"
    $content = $content -replace "{PUBLIC_CERT_URL}","$($package_base_url)/public_cert.crt"
    $script:install_instructions = $content
}

task MakeMsixChangelog {
    $content = $(Get-Content -Path "$($full_changelog_local_path)")
    $changelog_content = ""
    foreach ($line in $content){
        if($line -match "^\[([0-9]+)\].*$"){
            $timestamp = $Matches[1]
            if([int]$timestamp -gt [int]$previous_msix_package_timestamp){
                $changelog_content += "<li>$($line -replace "^\[[0-9]+\]\s*(.*)$","`$1")</li>`n"
            }
        }
    }
    $content = ""
    if($changelog_content){
        $content += "<article><header><h1>Changelog (Sublime Text $($channel) Package)</h1></header>`n<ul>`n"
        $content += $changelog_content
        $content += "</ul></article>`n"
    }
    $script:msix_changelog = $content
}

task MakePackageChangelog -Jobs ExtractPackage, {
    requires -Path "$($package_extract_dir)/changelog.txt"

    $old_version = [System.Version]::new("$previous_msix_package_build_number")
    $version = [int]"$($old_version.Major)$($old_version.Minor)"
    $version += 1
    $xml=[system.xml.linq.xelement]::parse("<root>" + $(get-content "$($package_extract_dir)/changelog.txt") + "</root>")
    $articles = $xml.descendants("article").where({[int] $($_.Element("h2").value -replace ".*?([0-9][0-9]+).*","`$1") -ge $version})
    $content = ""
    if($articles.count){
        $content += "<article><header><h1>Changelog (Sublime Text $($channel))</h1></header>`n"
        foreach ($j in $articles){$content += $j.toString()}
        $content += "</article>`n"
    }
    $script:package_changelog = $content
}

task MakeChangelog -Jobs MakePackageChangelog, MakeMsixChangelog, {
    $script:changelog = $msix_changelog + $package_changelog
    Set-Content -Path "$($changelog_local_path)" -Value $script:changelog
}

task MakeReleaseNote ?MakeInstallInstructions, MakeChangelog, {
    $script:release_note = $script:install_instructions + $script:changelog
    Set-Content -Path "$($release_note_local_path)" -Value $script:release_note
}

task CollectReleaseInfo -Jobs MakeReleaseNote, MakeChangelog, {
    $out_files["$($release_note_local_path)"] = "./"
    $out_files["$($changelog_local_path)"] = "./"

}

task CollectMsixPackage -Jobs MakeSignedMsixPackage, {
    $out_files["$($msix_package)"] = "./"
}

task CollectAppInstallerFile -Jobs MakeAppInstallerFile, {
    $out_files["$($appinstaller_local_path)"] = "./"

}

task CollectPublicCert -Jobs GetPublicCert, {
    $out_files["$($public_cert_local_path)"] = "./"
}

task CollectOutFiles CollectMsixPackage, ?CollectAppInstallerFile, CollectReleaseInfo, ?CollectPublicCert

task PrepareRelease -Jobs CollectOutFiles, MakeOutDir, {
    foreach($item in $out_files.GetEnumerator()){
        Copy-Item -Force -Path "$($item.Name)" -Destination "$($out_dir)/$($item.Value)" -Recurse
    }
}


task MakeBuildDir -If {! (Test-Path -Path $($build_dir) -Type Container)} {
    New-Item -Type Directory -Path "$($build_dir)"
}

task MakeOutDir -If {! (Test-Path -Path $($out_dir) -Type Container)} {
    New-Item -Type Directory -Path "$($out_dir)"
}

task CanUpdate -Jobs GetPreviousMsixPackageBuildNumber, GetPackageBuildNumber, {
    $prev = [System.Version]::new("$($previous_msix_package_build_number)")
    $cur = [System.Version]::new("$($package_build_number.SubString(0,1))","$($package_build_number.SubString(1))",0,0)
    $can_update = $false
    if($cur -gt $prev){
        $can_update = $true
    }
    $script:build_results["can_update"] = $can_update
}

task UpdateCheck CanUpdate, GetMsixPackageBuildNumber, GetPackageBuildNumber

Exit-Build {
    if($build_result){
        New-Variable -Name "$($build_result)" -Value $build_results -Scope Global -Force
    }
}

task . MakeBuildDir, ExtractPackage
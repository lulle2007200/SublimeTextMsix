#include "OpenHere.h"
#include <ShlObj.h>
#include <string>
#include <string_view>
#include <Shlwapi.h>
#include <filesystem>
#include <wil/stl.h>
#include <wil/filesystem.h>
#include <winrt/windows.applicationmodel.h>


IFACEMETHODIMP OpenHere::Invoke(IShellItemArray* psiItemArray, IBindCtx*)
{
    winrt::hstring location = winrt::Windows::ApplicationModel::Package::Current().InstalledPath();
    winrt::hstring path = location + L"\\Sublime\\sublime_text.exe";

    winrt::com_ptr<IShellItemArray> items;
    items.copy_from(psiItemArray);
    winrt::com_ptr<IShellItem> item = GetLocation(items);
    if (item) {

        wil::unique_cotaskmem_string name;
        if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &name))) {
            wil::unique_process_information process_info;
            STARTUPINFOEX startup_info{ 0 };
            startup_info.StartupInfo.cb = sizeof(startup_info);
            startup_info.StartupInfo.dwFlags = STARTF_USESHOWWINDOW;
            startup_info.StartupInfo.wShowWindow = SW_SHOWNORMAL;

            std::wstring cmd_line = L"-n \"" + std::wstring(name.get()) + "\"";

            if (CreateProcessW(path.data(),
                cmd_line.data(),
                nullptr,
                nullptr,
                false,
                EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                nullptr,
                nullptr,
                &startup_info.StartupInfo,
                &process_info)) {
                return S_OK;
            }
        }
    }

    return S_FALSE;
}

IFACEMETHODIMP OpenHere::GetToolTip(IShellItemArray*, LPWSTR* ppszInfoTip)
{
    *ppszInfoTip = nullptr;
    return E_NOTIMPL;
}

IFACEMETHODIMP OpenHere::GetTitle(IShellItemArray*, LPWSTR* ppszName)
{
    const std::wstring resource = L"Open in Sublime Text";

    return SHStrDupW(resource.c_str(), ppszName);
}

IFACEMETHODIMP OpenHere::GetState(IShellItemArray* psiItemArray, BOOL , EXPCMDSTATE* pCmdState)
{
    winrt::com_ptr<IShellItemArray> items;
    items.copy_from(psiItemArray);
    winrt::com_ptr<IShellItem> item = GetLocation(items);

    *pCmdState = ECS_HIDDEN;
    if (item) {
        SFGAOF attributes;
        const bool is_file_system_folder = item->GetAttributes(SFGAO_FILESYSTEM | SFGAO_FOLDER, &attributes) == S_OK;
        const bool is_compressed = item->GetAttributes(SFGAO_STREAM, &attributes) == S_OK;

        if (is_file_system_folder && !is_compressed) {
            *pCmdState = ECS_ENABLED;
        }
    }
    return S_OK;
}

IFACEMETHODIMP OpenHere::GetIcon(IShellItemArray*, LPWSTR* ppszIcon)
{
    winrt::hstring location = winrt::Windows::ApplicationModel::Package::Current().InstalledPath();
    winrt::hstring path = location + L"\\Sublime\\sublime_text.exe,-103";

    return SHStrDupW(path.c_str(), ppszIcon);
}

IFACEMETHODIMP OpenHere::GetFlags(EXPCMDFLAGS* pFlags)
{
    *pFlags = ECF_DEFAULT;
    return S_OK;
}

IFACEMETHODIMP OpenHere::GetCanonicalName(GUID* pguidCommandName)
{
    *pguidCommandName = __uuidof(this);
    return S_OK;
}

IFACEMETHODIMP OpenHere::EnumSubCommands(IEnumExplorerCommand** ppEnum)
{
    *ppEnum = nullptr;
    return E_NOTIMPL;
}

IFACEMETHODIMP OpenHere::SetSite(IUnknown* site) noexcept
{
    this->site.copy_from(site);
    return S_OK;
}

IFACEMETHODIMP OpenHere::GetSite(REFIID iid, void** site) noexcept
{
    if (this->site) {
        return this->site->QueryInterface(iid, site);
    }
    return E_FAIL;
}

winrt::com_ptr<IShellItem> OpenHere::GetLocation(winrt::com_ptr<IShellItemArray> item_array) {
    winrt::com_ptr<IShellItem> item;

    if (item_array) {
        DWORD count{};
        item_array->GetCount(&count);
        if (count) {
            item_array->GetItemAt(0, item.put());
        }
    }

    if (!item) {
        item = GetLocationFromSite();
    }

    return item;
}

winrt::com_ptr<IShellItem> OpenHere::GetLocationFromSite() {
    winrt::com_ptr<IShellItem> item;
    if (site) {
        winrt::com_ptr<IServiceProvider> service_provider;
        if (site.try_as(service_provider)) {
            winrt::com_ptr<IFolderView> folder_view;
            service_provider->QueryService<IFolderView>(SID_SFolderView, folder_view.put());
            if(folder_view){
                item.try_capture(folder_view, &IFolderView::GetFolder);
            }
        }
    }
    return item;
}

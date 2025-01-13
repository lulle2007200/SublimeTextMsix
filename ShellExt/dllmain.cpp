#include <wrl.h>
#include <cstdio>

STDAPI DllCanUnloadNow()
{
    if(Microsoft::WRL::Module<Microsoft::WRL::InProc>::GetModule().Terminate()){
        return S_OK;
    }
    return S_FALSE;
}

STDAPI DllGetActivationFactory(HSTRING activatable_clsid, IActivationFactory **factory)
{
    return Microsoft::WRL::Module<Microsoft::WRL::InProc>::GetModule().GetActivationFactory(activatable_clsid, factory);
}

STDAPI DllGetClassObject(REFCLSID clsid, REFIID iid, void **v)
{
    return Microsoft::WRL::Module<Microsoft::WRL::InProc>::GetModule().GetClassObject(clsid, iid, v);
}

BOOL WINAPI DllMain(HINSTANCE hinst, DWORD reason, void *reserved)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        //FILE* stream;
        //AllocConsole();
        //freopen_s(&stream, "CONOUT$", "w", stdout);
        DisableThreadLibraryCalls(hinst);
    }
    return true;
}

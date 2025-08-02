#include "RenderAPI.h"
#include "PlatformBase.h"
#include "Unity/IUnityGraphics.h"

RenderAPI* CreateRenderAPI(UnityGfxRenderer apiType)
{
#	if SUPPORT_METAL
	if (apiType == kUnityGfxRendererMetal)
	{
		extern RenderAPI* CreateRenderAPI_Metal();
		return CreateRenderAPI_Metal();
	}
#	endif // if SUPPORT_METAL
    
	// Unknown or unsupported graphics API
	return NULL;
}

// 低レベルレンダリングUnityプラグインの例

#include "PlatformBase.h"
#include "RenderAPI.h"

#include <assert.h>
#include <math.h>
#include <vector>

// --------------------------------------------------------------------------
// SetTextureFromUnity、スクリプトの1つから呼び出されるエクスポート関数の例。

static void* g_TextureHandle = NULL;
static int   g_TextureWidth  = 0;
static int   g_TextureHeight = 0;
static void* g_UpscaledTextureHandle = NULL;
static int   g_UpscaledTextureWidth  = 0;
static int   g_UpscaledTextureHeight = 0;

extern "C" void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API SetTextureFromUnity(void* textureHandle, int w, int h, void* upscaled, int upscaledW, int upscaledH)
{
    // スクリプトが初期化時にこれを呼び出します。ここではテクスチャポインタを記憶するだけです。
    // プラグインレンダリングイベントから毎フレームテクスチャピクセルを更新します（テクスチャ更新は
    // レンダリングスレッドで実行される必要があります）。
    g_TextureHandle = textureHandle;
    g_TextureWidth = w;
    g_TextureHeight = h;
    
    g_UpscaledTextureHandle = upscaled;
    g_UpscaledTextureWidth = upscaledW;
    g_UpscaledTextureHeight = upscaledH;
}

extern "C" int Test ()
{
    return 123;
}

// --------------------------------------------------------------------------
// UnitySetInterfaces

static void UNITY_INTERFACE_API OnGraphicsDeviceEvent(UnityGfxDeviceEventType eventType);

static IUnityInterfaces* s_UnityInterfaces = NULL;
static IUnityGraphics* s_Graphics = NULL;

extern "C" void	UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginLoad(IUnityInterfaces* unityInterfaces)
{
	s_UnityInterfaces = unityInterfaces;
	s_Graphics = s_UnityInterfaces->Get<IUnityGraphics>();
	s_Graphics->RegisterDeviceEventCallback(OnGraphicsDeviceEvent);

	// プラグインロード時にOnGraphicsDeviceEvent(initialize)を手動で実行
	OnGraphicsDeviceEvent(kUnityGfxDeviceEventInitialize);
}

extern "C" void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginUnload()
{
	s_Graphics->UnregisterDeviceEventCallback(OnGraphicsDeviceEvent);
}

// --------------------------------------------------------------------------
// GraphicsDeviceEvent

static RenderAPI* s_CurrentAPI = NULL;
static UnityGfxRenderer s_DeviceType = kUnityGfxRendererNull;

static void UNITY_INTERFACE_API OnGraphicsDeviceEvent(UnityGfxDeviceEventType eventType)
{
	// 初期化時にグラフィックスAPI実装を作成
	if (eventType == kUnityGfxDeviceEventInitialize)
	{
		assert(s_CurrentAPI == NULL);
		s_DeviceType = s_Graphics->GetRenderer();
		s_CurrentAPI = CreateRenderAPI(s_DeviceType);
	}

	// 実装にデバイス関連イベントを処理させる
	if (s_CurrentAPI)
	{
		s_CurrentAPI->ProcessDeviceEvent(eventType, s_UnityInterfaces);
	}

	// シャットダウン時にグラフィックスAPI実装をクリーンアップ
	if (eventType == kUnityGfxDeviceEventShutdown)
	{
		delete s_CurrentAPI;
		s_CurrentAPI = NULL;
		s_DeviceType = kUnityGfxRendererNull;
	}
}

// --------------------------------------------------------------------------
// OnRenderEvent
// これはGL.IssuePluginEventスクリプト呼び出しで呼ばれます。eventIDは
// IssuePluginEventに渡される整数です。この例では、その値を無視します。

static void ModifyTexturePixels()
{
	void* textureHandle = g_TextureHandle;
	int width = g_TextureWidth;
	int height = g_TextureHeight;
	if (!textureHandle)
		return;
    
    
    void* upscaledTextureHandle = g_UpscaledTextureHandle;
    int upscaledWidth = g_UpscaledTextureWidth;
    int upscaledHeight = g_UpscaledTextureHeight;
    if (!upscaledTextureHandle)
        return;

	int textureRowPitch;
	void* textureDataPtr = s_CurrentAPI->BeginModifyTexture(textureHandle, width, height, &textureRowPitch);
	s_CurrentAPI->EndModifyTexture(textureHandle, width, height, upscaledTextureHandle, upscaledWidth, upscaledHeight);
}

static void UNITY_INTERFACE_API OnRenderEvent(int eventID)
{
	// 不明/サポートされていないグラフィックスデバイスタイプ？何もしない
	if (s_CurrentAPI == NULL)
		return;

	if (eventID == 1)
	{
        ModifyTexturePixels();
	}
}

// --------------------------------------------------------------------------
// GetRenderEventFunc、レンダリングイベントコールバック関数を取得するために使用されるエクスポート関数の例。

extern "C" UnityRenderingEvent UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API GetRenderEventFunc()
{
	return OnRenderEvent;
}

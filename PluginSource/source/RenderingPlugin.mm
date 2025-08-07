// 低レベルレンダリングUnityプラグインの例

#include "PlatformBase.h"
#include "RenderAPI.h"

#include <assert.h>
#include <math.h>
#include <vector>
#include <string>

#include "Unity/IUnityGraphicsMetal.h"
#include "DebugUtility.hpp"
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>

// --------------------------------------------------------------------------
// SetTextureFromUnity、スクリプトの1つから呼び出されるエクスポート関数の例。

void* g_TextureHandle = NULL;
int   g_TextureWidth  = 0;
int   g_TextureHeight = 0;

void* g_UpscaledTextureHandle = NULL;
int   g_UpscaledTextureWidth  = 0;
int   g_UpscaledTextureHeight = 0;

IUnityGraphicsMetal*   g_MetalGraphics;
id<MTLDevice>          g_Device;
id<MTLCommandQueue>    g_CommandQueue;
id<MTLFXSpatialScaler> g_SpatialScaler;
float                  g_UpscaleScale;

extern "C" int Test ()
{
    return 123;
}

extern "C" void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API SetLogCallback(void (*logCallback)(const char*), void (*logErrorCallback)(const char*))
{
    g_logCallback = logCallback;
    g_logErrorCallback = logErrorCallback;
}

extern "C" void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API SetTextureFromUnity(
    void* textureHandle,
    int w,
    int h,
    void* upscaled,
    int upscaledW,
    int upscaledH)
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

// --------------------------------------------------------------------------
// UnitySetInterfaces

void UNITY_INTERFACE_API OnGraphicsDeviceEvent(UnityGfxDeviceEventType eventType);
void ProcessDeviceEvent(UnityGfxDeviceEventType type, IUnityInterfaces* interfaces);

IUnityInterfaces* s_UnityInterfaces = NULL;
IUnityGraphics* s_Graphics = NULL;

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

UnityGfxRenderer s_DeviceType = kUnityGfxRendererNull;

void UNITY_INTERFACE_API OnGraphicsDeviceEvent(UnityGfxDeviceEventType eventType)
{
	// 初期化時にグラフィックスAPI実装を作成
	if (eventType == kUnityGfxDeviceEventInitialize)
	{
		s_DeviceType = s_Graphics->GetRenderer();
	}

	// 実装にデバイス関連イベントを処理させる
    ProcessDeviceEvent(eventType, s_UnityInterfaces);

	// シャットダウン時にグラフィックスAPI実装をクリーンアップ
	if (eventType == kUnityGfxDeviceEventShutdown)
	{
		s_DeviceType = kUnityGfxRendererNull;
	}
}


// --------------------------------------------------------------------------
// OnRenderEvent
// これはGL.IssuePluginEventスクリプト呼び出しで呼ばれます。eventIDは
// IssuePluginEventに渡される整数です。この例では、その値を無視します。

void CreateResources()
{
    g_UpscaleScale = 2.0f;
    // MetalFXスケーラーは動的に作成するため、ここでは初期化しない
    g_SpatialScaler = nil;
}

void ProcessDeviceEvent(UnityGfxDeviceEventType type, IUnityInterfaces* interfaces)
{
    if (type == kUnityGfxDeviceEventInitialize)
    {
        g_MetalGraphics = interfaces->Get<IUnityGraphicsMetal>();
        
        // Metalデバイスとコマンドキューを取得
        g_Device = g_MetalGraphics->MetalDevice();
        g_CommandQueue = [g_Device newCommandQueue];
        
        CreateResources();
    }
    else if (type == kUnityGfxDeviceEventShutdown)
    {
        // リソースを解放
        g_CommandQueue = nil;
        g_Device = nil;
        g_SpatialScaler = nil;
    }
}

void Upscale()
{
    LOG("log by objective-cpp");
    
    // Unity側から受け取ったGPUテクスチャポインタを直接使用
    id<MTLTexture> tex = (__bridge id<MTLTexture>)g_TextureHandle;
    id<MTLTexture> upscaledTex = (__bridge id<MTLTexture>)g_UpscaledTextureHandle;
    
    // MetalFXを使用したGPU間直接アップスケーリング処理
    if (!g_Device || !g_CommandQueue || !tex)
    {
        return;
    }
    
    // MetalFXスケーラーを作成（必要に応じて）
    if (!g_SpatialScaler ||
        g_SpatialScaler.inputWidth != g_TextureWidth ||
        g_SpatialScaler.inputHeight != g_TextureHeight)
    {
        MTLFXSpatialScalerDescriptor* desc = [[MTLFXSpatialScalerDescriptor alloc] init];
        
        desc.inputWidth = g_TextureWidth;
        desc.inputHeight = g_TextureHeight;
        desc.outputWidth = upscaledTex.width;
        desc.outputHeight = upscaledTex.height;
        desc.colorTextureFormat = tex.pixelFormat;
        desc.outputTextureFormat = upscaledTex.pixelFormat;
        desc.colorProcessingMode = MTLFXSpatialScalerColorProcessingModePerceptual;
        
        g_SpatialScaler = [desc newSpatialScalerWithDevice:g_Device];
    }
    
    if (upscaledTex && g_SpatialScaler)
    {
        // コマンドバッファを作成
        id<MTLCommandBuffer> commandBuffer = [g_CommandQueue commandBuffer];
        if (commandBuffer)
        {
            // MetalFXスケーラーを使用してGPU間直接アップスケーリング実行
            g_SpatialScaler.colorTexture = tex;
            g_SpatialScaler.outputTexture = upscaledTex;
            [g_SpatialScaler encodeToCommandBuffer:commandBuffer];
            
            // コマンドを実行
            [commandBuffer commit];
            [commandBuffer waitUntilCompleted];
        }
    }
}

void UNITY_INTERFACE_API OnRenderEvent(int eventID)
{
	if (eventID == 1)
	{
        Upscale();
	}
}

// --------------------------------------------------------------------------
// GetRenderEventFunc、レンダリングイベントコールバック関数を取得するために使用されるエクスポート関数の例。

extern "C" UnityRenderingEvent UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API GetRenderEventFunc()
{
	return OnRenderEvent;
}

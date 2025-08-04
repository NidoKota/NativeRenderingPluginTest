// 低レベルレンダリングUnityプラグインの例

#include "PlatformBase.h"
#include "RenderAPI.h"

#include <assert.h>
#include <math.h>
#include <vector>

#include "Unity/IUnityGraphicsMetal.h"
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>

// --------------------------------------------------------------------------
// SetTextureFromUnity、スクリプトの1つから呼び出されるエクスポート関数の例。

extern "C" int Test ()
{
    return 123;
}

static void* g_TextureHandle = NULL;
static int   g_TextureWidth  = 0;
static int   g_TextureHeight = 0;

static void* g_UpscaledTextureHandle = NULL;
static int   g_UpscaledTextureWidth  = 0;
static int   g_UpscaledTextureHeight = 0;

static IUnityGraphicsMetal*   m_MetalGraphics;
static id<MTLDevice>          m_Device;
static id<MTLCommandQueue>    m_CommandQueue;
static id<MTLFXSpatialScaler> m_SpatialScaler;
static float                  m_UpscaleScale;

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

void Upscale()
{
    // Unity側から受け取ったGPUテクスチャポインタを直接使用
    id<MTLTexture> tex = (__bridge id<MTLTexture>)g_TextureHandle;
    id<MTLTexture> upscaledTex = (__bridge id<MTLTexture>)g_UpscaledTextureHandle;
    
    // MetalFXを使用したGPU間直接アップスケーリング処理
    if (m_Device && m_CommandQueue && tex)
    {
        // MetalFXスケーラーを作成（必要に応じて）
        if (!m_SpatialScaler ||
            m_SpatialScaler.inputWidth != g_TextureWidth ||
            m_SpatialScaler.inputHeight != g_TextureHeight)
        {
            MTLFXSpatialScalerDescriptor* desc = [[MTLFXSpatialScalerDescriptor alloc] init];
            
            desc.inputWidth = g_TextureWidth;
            desc.inputHeight = g_TextureHeight;
            desc.outputWidth = upscaledTex.width;
            desc.outputHeight = upscaledTex.height;
            desc.colorTextureFormat = tex.pixelFormat;
            desc.outputTextureFormat = upscaledTex.pixelFormat;
            desc.colorProcessingMode = MTLFXSpatialScalerColorProcessingModePerceptual;
            
            m_SpatialScaler = [desc newSpatialScalerWithDevice:m_Device];
        }
        
        if (upscaledTex && m_SpatialScaler)
        {
            // コマンドバッファを作成
            id<MTLCommandBuffer> commandBuffer = [m_CommandQueue commandBuffer];
            if (commandBuffer)
            {
                // MetalFXスケーラーを使用してGPU間直接アップスケーリング実行
                m_SpatialScaler.colorTexture = tex;
                m_SpatialScaler.outputTexture = upscaledTex;
                [m_SpatialScaler encodeToCommandBuffer:commandBuffer];
                
                // コマンドを実行
                [commandBuffer commit];
                [commandBuffer waitUntilCompleted];
            }
        }
    }
    
    // CPUメモリバッファは使用していないため、解放処理も不要
}

void RenderAPI_Metal::ProcessDeviceEvent(UnityGfxDeviceEventType type, IUnityInterfaces* interfaces)
{
    if (type == kUnityGfxDeviceEventInitialize)
    {
        m_MetalGraphics = interfaces->Get<IUnityGraphicsMetal>();
        
        // Metalデバイスとコマンドキューを取得
        m_Device = m_MetalGraphics->MetalDevice();
        m_CommandQueue = [m_Device newCommandQueue];
        
        CreateResources();
        CreateUpscaleResources();
    }
    else if (type == kUnityGfxDeviceEventShutdown)
    {
        // リソースを解放
        m_CommandQueue = nil;
        m_Device = nil;
        m_SpatialScaler = nil;
    }
}

static void UNITY_INTERFACE_API OnRenderEvent(int eventID)
{
	// 不明/サポートされていないグラフィックスデバイスタイプ？何もしない
    if (s_CurrentAPI == NULL)
    {
        return;
    }

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

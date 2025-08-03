#include "RenderAPI.h"
#include "PlatformBase.h"

// Metal implementation of RenderAPI.

#if SUPPORT_METAL

#include "Unity/IUnityGraphicsMetal.h"
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>

class RenderAPI_Metal : public RenderAPI
{
public:
	RenderAPI_Metal();
	virtual ~RenderAPI_Metal() { }

	virtual void ProcessDeviceEvent(UnityGfxDeviceEventType type, IUnityInterfaces* interfaces);

	virtual bool GetUsesReverseZ() { return true; }

	virtual void DrawSimpleTriangles(const float worldMatrix[16], int triangleCount, const void* verticesFloat3Byte4);

	virtual void* BeginModifyTexture(void* textureHandle, int textureWidth, int textureHeight, int* outRowPitch);
	virtual void EndModifyTexture(void* textureHandle, int textureWidth, int textureHeight, int rowPitch, void* dataPtr);

	virtual void* BeginModifyVertexBuffer(void* bufferHandle, size_t* outBufferSize);
	virtual void EndModifyVertexBuffer(void* bufferHandle);

private:
	void CreateResources();
	void CreateUpscaleResources();

private:
	IUnityGraphicsMetal*	m_MetalGraphics;
	id<MTLDevice>			m_Device;
	id<MTLCommandQueue>		m_CommandQueue;
	
	// アップスケーリング用リソース
	id<MTLTexture>			m_UpscaledTexture;
	id<MTLFXSpatialScaler>	m_SpatialScaler;
	float					m_UpscaleScale;
};


RenderAPI* CreateRenderAPI_Metal()
{
	return new RenderAPI_Metal();
}

void RenderAPI_Metal::CreateResources()
{
}

void RenderAPI_Metal::CreateUpscaleResources()
{
    m_UpscaleScale = 2.0f;
    // MetalFXスケーラーは動的に作成するため、ここでは初期化しない
    m_SpatialScaler = nil;
}

RenderAPI_Metal::RenderAPI_Metal()
	: m_Device(nil)
	, m_CommandQueue(nil)
	, m_UpscaledTexture(nil)
	, m_SpatialScaler(nil)
	, m_UpscaleScale(1.0f)
{
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
        m_UpscaledTexture = nil;
        m_SpatialScaler = nil;
	}
}

void RenderAPI_Metal::DrawSimpleTriangles(const float worldMatrix[16], int triangleCount, const void* verticesFloat3Byte4)
{
}

void* RenderAPI_Metal::BeginModifyTexture(void* textureHandle, int textureWidth, int textureHeight, int* outRowPitch)
{
	const int rowPitch = textureWidth * 4;
	// Just allocate a system memory buffer here for simplicity
	unsigned char* data = new unsigned char[rowPitch * textureHeight];
	*outRowPitch = rowPitch;
	return data;
}

void RenderAPI_Metal::EndModifyTexture(void* textureHandle, int textureWidth, int textureHeight, int rowPitch, void* dataPtr)
{
	id<MTLTexture> tex = (__bridge id<MTLTexture>)textureHandle;
	
	// 元のテクスチャデータを更新
	[tex replaceRegion:MTLRegionMake3D(0,0,0, textureWidth,textureHeight,1) mipmapLevel:0 withBytes:dataPtr bytesPerRow:rowPitch];
    
	// MetalFXを使用したアップスケーリング処理
	if (m_Device && m_CommandQueue)
    {
		// アップスケール後のサイズを計算
		int upscaledWidth = (int)(textureWidth * m_UpscaleScale);
		int upscaledHeight = (int)(textureHeight * m_UpscaleScale);
		
		// アップスケール用出力テクスチャを作成（必要に応じて）
		if (!m_UpscaledTexture || 
			m_UpscaledTexture.width != upscaledWidth || 
			m_UpscaledTexture.height != upscaledHeight)
        {
			MTLTextureDescriptor* textureDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:tex.pixelFormat
																								   width:upscaledWidth
																								  height:upscaledHeight
																							   mipmapped:NO];
			textureDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
			textureDesc.storageMode = MTLStorageModePrivate;
			m_UpscaledTexture = [m_Device newTextureWithDescriptor:textureDesc];
		}
		
		// MetalFXスケーラーを作成（必要に応じて）
		if (!m_SpatialScaler || 
			m_SpatialScaler.inputWidth != textureWidth ||
			m_SpatialScaler.inputHeight != textureHeight)
        {
			MTLFXSpatialScalerDescriptor* desc = [[MTLFXSpatialScalerDescriptor alloc] init];
			desc.inputWidth = textureWidth;
			desc.inputHeight = textureHeight;
			desc.outputWidth = upscaledWidth;
			desc.outputHeight = upscaledHeight;
			desc.colorTextureFormat = tex.pixelFormat;
			desc.outputTextureFormat = m_UpscaledTexture.pixelFormat;
			desc.colorProcessingMode = MTLFXSpatialScalerColorProcessingModePerceptual;
			
			m_SpatialScaler = [desc newSpatialScalerWithDevice:m_Device];
		}
		
		if (m_UpscaledTexture && m_SpatialScaler)
        {
			// コマンドバッファを作成
			id<MTLCommandBuffer> commandBuffer = [m_CommandQueue commandBuffer];
			if (commandBuffer)
            {
				// MetalFXスケーラーを使用してアップスケーリング実行
				m_SpatialScaler.colorTexture = tex;
				m_SpatialScaler.outputTexture = m_UpscaledTexture;
				[m_SpatialScaler encodeToCommandBuffer:commandBuffer];
				
				// コマンドを実行
				[commandBuffer commit];
				[commandBuffer waitUntilCompleted];
				
				NSLog(@"MetalFX upscaling completed: %dx%d -> %dx%d", 
					  textureWidth, textureHeight,
					  (int)m_UpscaledTexture.width, (int)m_UpscaledTexture.height);
			}
		}
	}
	
	// メモリバッファを解放
	delete[](unsigned char*)dataPtr;
}

void* RenderAPI_Metal::BeginModifyVertexBuffer(void* bufferHandle, size_t* outBufferSize)
{
    return NULL;
}

void RenderAPI_Metal::EndModifyVertexBuffer(void* bufferHandle)
{
}

#endif // #if SUPPORT_METAL

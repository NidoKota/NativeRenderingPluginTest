#include "RenderAPI.h"
#include "PlatformBase.h"

// Metal implementation of RenderAPI.

#if SUPPORT_METAL

#include "Unity/IUnityGraphicsMetal.h"
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

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
	MPSImageLanczosScale*	m_LanczosScaler;
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
    m_LanczosScaler = [[MPSImageLanczosScale alloc] initWithDevice:m_Device];
}

RenderAPI_Metal::RenderAPI_Metal()
	: m_Device(nil)
	, m_CommandQueue(nil)
	, m_UpscaledTexture(nil)
	, m_LanczosScaler(nil)
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
        m_LanczosScaler = nil;
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
    
	// アップスケーリング処理を実行
	if (m_Device && m_CommandQueue && m_LanczosScaler)
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
			textureDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
			m_UpscaledTexture = [m_Device newTextureWithDescriptor:textureDesc];
		}
		
		if (m_UpscaledTexture)
        {
			// コマンドバッファを作成
			id<MTLCommandBuffer> commandBuffer = [m_CommandQueue commandBuffer];
			if (commandBuffer)
            {
				// Lanczosスケーラーを使用してアップスケーリング実行
				[m_LanczosScaler encodeToCommandBuffer:commandBuffer
										 sourceTexture:tex
								    destinationTexture:m_UpscaledTexture];
				
				// コマンドを実行
				[commandBuffer commit];
				[commandBuffer waitUntilCompleted];
				
				NSLog(@"Metal upscaling completed: %dx%d -> %dx%d", 
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

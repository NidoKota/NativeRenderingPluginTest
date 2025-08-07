using System;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class UpscaleFeature : ScriptableRendererFeature
{
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void LogCallbackInternal([MarshalAs(UnmanagedType.LPStr)] string message);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void LogErrorCallbackInternal([MarshalAs(UnmanagedType.LPStr)] string message);
    
    [Serializable]
    public class UpscaleSettings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
        public float upscaleScale = 2.0f;
        [Range(0.1f, 1.0f)]
        public float renderScale = 0.5f; // 低解像度レンダリングのスケール
    }

    public UpscaleSettings settings = new UpscaleSettings();
    private UpscalePass upscalePass;
    private GCHandle _logCallbackInternalHandle;
    private GCHandle _logErrorCallbackInternalHandle;

    private void CallLogCallbackInternal(string str)
    {
        Debug.Log(str);
    }
        
    private void CallLogErrorCallbackInternal(string str)
    {
        Debug.LogError(str);
    }
    
    [DllImport("RenderingPlugin")]
    private static extern void SetLogCallback(LogCallbackInternal logCallback, LogErrorCallbackInternal logErrorCallback);
    
    // ネイティブプラグインの関数をインポート
#if (PLATFORM_IOS || PLATFORM_TVOS || PLATFORM_BRATWURST || PLATFORM_SWITCH) && !UNITY_EDITOR
    [DllImport("__Internal")]
#else
    [DllImport("RenderingPlugin")]
#endif
    private static extern void SetTextureFromUnity(nint texture, int w, int h, nint upscaled, int upscaledW, int upscaledH);

#if (PLATFORM_IOS || PLATFORM_TVOS || PLATFORM_BRATWURST || PLATFORM_SWITCH) && !UNITY_EDITOR
    [DllImport("__Internal")]
#else
    [DllImport("RenderingPlugin")]
#endif
    private static extern nint GetRenderEventFunc();
    
    [DllImport("RenderingPlugin")] 
    private static extern int Test();

    public override void Create()
    {
        upscalePass = new UpscalePass(settings);

        _logCallbackInternalHandle = GCHandle.Alloc((LogCallbackInternal)CallLogCallbackInternal);
        _logErrorCallbackInternalHandle = GCHandle.Alloc((LogErrorCallbackInternal)CallLogErrorCallbackInternal);
            
        SetLogCallback((LogCallbackInternal)_logCallbackInternalHandle.Target, (LogErrorCallbackInternal)_logErrorCallbackInternalHandle.Target);
    }
    
    protected override void Dispose(bool disposing)
    {
        _logCallbackInternalHandle.Free();
        _logErrorCallbackInternalHandle.Free();
    }
    
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (upscalePass == null)
        {
            return;
        }
        
        // カメラの解像度を下げる
        renderingData.cameraData.renderScale = settings.renderScale;
            
        renderer.EnqueuePass(upscalePass);
    }

    // カスタムレンダーパスクラス
    private class UpscalePass : ScriptableRenderPass
    {
        private const string ProfilerTag = "UpscalePass";
        
        private readonly UpscaleSettings m_Settings;
        private RTHandle m_UpscaledTexture;

        public UpscalePass(UpscaleSettings settings)
        {
            m_Settings = settings;
            renderPassEvent = settings.renderPassEvent;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 最終的な高解像度テクスチャのディスクリプタを作成
            var descriptor = renderingData.cameraData.cameraTargetDescriptor;
            
            // 元の解像度を保持
            var originalWidth = descriptor.width;
            var originalHeight = descriptor.height;
            
            // アップスケール後のサイズを計算
            descriptor.width = Mathf.RoundToInt(originalWidth * m_Settings.upscaleScale);
            descriptor.height = Mathf.RoundToInt(originalHeight * m_Settings.upscaleScale);
            descriptor.depthBufferBits = 0; // カラーテクスチャのみ
            
            // アップスケール用テンポラリテクスチャを確保
            RenderingUtils.ReAllocateIfNeeded(ref m_UpscaledTexture, descriptor, name: "_UpscaledTexture");
            
            // 高解像度テクスチャを最終出力先として設定
            ConfigureTarget(m_UpscaledTexture);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(ProfilerTag);

            using (new ProfilingScope(cmd, new ProfilingSampler(ProfilerTag)))
            {
                // 現在のカメラターゲット（低解像度）を取得
                ScriptableRenderer renderer = renderingData.cameraData.renderer;
                RTHandle sourceTexture = renderer.cameraColorTargetHandle;

                // ネイティブプラグインにソーステクスチャを渡す
                if (sourceTexture != null)
                {
                    RenderTexture sourceRT = sourceTexture.rt;
                    RenderTexture upscaledRT = m_UpscaledTexture.rt;
                    
                    if (sourceRT != null && upscaledRT != null)
                    {
                        SetTextureFromUnity(
                            sourceRT.GetNativeTexturePtr(), sourceRT.width, sourceRT.height,
                            upscaledRT.GetNativeTexturePtr(), upscaledRT.width, upscaledRT.height);
                        
                        // ネイティブプラグインのアップスケール処理を実行
                        cmd.IssuePluginEvent(GetRenderEventFunc(), 1);
                    }
                }
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            
        }
    }
}
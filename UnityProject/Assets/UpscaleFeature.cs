using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System.Runtime.InteropServices;

public class UpscaleFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class UpscaleSettings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
        public float upscaleScale = 2.0f;
        [Range(0.1f, 1.0f)]
        public float renderScale = 0.5f; // 低解像度レンダリングのスケール
    }

    public UpscaleSettings settings = new UpscaleSettings();
    private UpscalePass upscalePass;

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

    public override void Create()
    {
        upscalePass = new UpscalePass(settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (upscalePass != null)
        {
            // カメラの解像度を下げる
            renderingData.cameraData.renderScale = settings.renderScale;
            
            renderer.EnqueuePass(upscalePass);
        }
    }

    // カスタムレンダーパスクラス
    private class UpscalePass : ScriptableRenderPass
    {
        private UpscaleSettings settings;
        private RTHandle upscaledTexture;
        private string profilerTag = "UpscalePass";

        public UpscalePass(UpscaleSettings settings)
        {
            this.settings = settings;
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
            descriptor.width = Mathf.RoundToInt(originalWidth * settings.upscaleScale);
            descriptor.height = Mathf.RoundToInt(originalHeight * settings.upscaleScale);
            descriptor.depthBufferBits = 0; // カラーテクスチャのみ
            
            // アップスケール用テンポラリテクスチャを確保
            RenderingUtils.ReAllocateIfNeeded(ref upscaledTexture, descriptor, name: "_UpscaledTexture");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(profilerTag);

            using (new ProfilingScope(cmd, new ProfilingSampler(profilerTag)))
            {
                // 現在のカメラターゲット（低解像度）を取得
                var renderer = renderingData.cameraData.renderer;
                var sourceTexture = renderer.cameraColorTargetHandle;

                // ネイティブプラグインにソーステクスチャを渡す
                if (sourceTexture != null)
                {
                    var sourceRT = sourceTexture.rt;
                    if (sourceRT != null)
                    {
                        SetTextureFromUnity(sourceRT.GetNativeTexturePtr(), sourceRT.width, sourceRT.height);

                        // ネイティブプラグインのアップスケール処理を実行
                        cmd.IssuePluginEvent(GetRenderEventFunc(), 1);
                    }
                }

                // 最終結果をカメラターゲットにコピー
                // カメラターゲットのサイズを元に戻す必要がある場合
                var finalTarget = renderer.cameraColorTarget;
                if (finalTarget != upscaledTexture)
                {
                    Blit(cmd, upscaledTexture, finalTarget);
                }
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            // テンポラリテクスチャのクリーンアップ
            // RTHandleは自動的に管理されるため、明示的な解放は不要
            // ただし、nullチェックは行う
            if (upscaledTexture != null)
            {
                // RTHandleSystemが管理するため、手動でReleaseしない
            }
            
            if (tempTexture != null)
            {
                // 同様にRTHandleSystemが管理
            }
        }

        public override void FrameCleanup(CommandBuffer cmd)
        {
            base.FrameCleanup(cmd);
        }
    }
}
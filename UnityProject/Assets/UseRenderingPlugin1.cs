using UnityEngine;
using System;
using System.Collections;
using System.Runtime.InteropServices;
using UnityEngine.Rendering;


public class UseRenderingPlugin1 : MonoBehaviour
{
    // また、Unityのテクスチャへのネイティブポインタも渡します。
    // プラグインはネイティブコードからテクスチャデータを埋めます。
#if (PLATFORM_IOS || PLATFORM_TVOS || PLATFORM_BRATWURST || PLATFORM_SWITCH) && !UNITY_EDITOR
    [DllImport("__Internal")]
#else
    [DllImport("RenderingPlugin")]
#endif
    private static extern void SetTextureFromUnity(System.IntPtr texture, int w, int h);

#if (PLATFORM_IOS || PLATFORM_TVOS || PLATFORM_BRATWURST || PLATFORM_SWITCH) && !UNITY_EDITOR
    [DllImport("__Internal")]
#else
    [DllImport("RenderingPlugin")]
#endif
    private static extern IntPtr GetRenderEventFunc();

    private void Start()
    {
        CreateTextureAndPassToPlugin();
        StartCoroutine(CallPluginAtEndOfFrames());
    }

    private void CreateTextureAndPassToPlugin()
    {
        // テクスチャを作成
        Texture2D tex = new Texture2D(256, 256, TextureFormat.ARGB32, false);
        // ピクセルをはっきり見えるようにポイントフィルタリングを設定
        tex.filterMode = FilterMode.Point;
        // Apply()を呼び出して実際にGPUにアップロード
        tex.Apply();

        // マテリアルにテクスチャを設定
        GetComponent<Renderer>().material.mainTexture = tex;

        // テクスチャポインタをプラグインに渡す
        SetTextureFromUnity(tex.GetNativeTexturePtr(), tex.width, tex.height);
    }
    
    private IEnumerator CallPluginAtEndOfFrames()
    {
        while (true)
        {
            // Wait until all frame rendering is done
            yield return new WaitForEndOfFrame();

            // Issue a plugin event with arbitrary integer identifier.
            // The plugin can distinguish between different
            // things it needs to do based on this ID.
            // On some backends the choice of eventID matters e.g on DX12 where
            // eventID == 1 means the plugin callback will be called from the render thread
            // and eventID == 2 means the callback is called from the submission thread
            GL.IssuePluginEvent(GetRenderEventFunc(), 1);
        }
    }
}

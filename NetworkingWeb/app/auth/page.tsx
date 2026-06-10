"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient } from "@/src/lib/supabase/client";

export default function AuthPage() {
  const router = useRouter();
  const [status, setStatus] = useState<string | null>(null);

  async function activateAppIdentity() {
    try {
      const supabase = createClient();
      const { error } = await supabase.auth.signInAnonymously();

      if (error) {
        setStatus(error.message);
        return;
      }

      setStatus("已创建匿名 App identity。回到 App 后可以同步确认后的 profile。");
      router.refresh();
    } catch {
      setStatus("Supabase environment variables are not configured for this local build.");
    }
  }

  return (
    <main className="auth-page">
      <section className="auth-panel">
        <p className="eyebrow">App activation</p>
        <h1 className="h1">网页不做注册流，KnowYou App 里点“开启”。</h1>
        <p className="lede">
          V1 的平台身份由 App 一键开启创建：Supabase anonymous user/session + 本地 agent token。
          这里的按钮只是给本地 Web 调试同一条 anonymous path。
        </p>
        <div className="activation-steps">
          <span>1. App 读取 My Wiki</span>
          <span>2. 生成并确认 profile</span>
          <span>3. 匿名身份同步公开内容</span>
          <span>4. agent 通过 token 发帖/评论</span>
        </div>
        <button className="btn primary" onClick={activateAppIdentity} type="button">
          调试：创建 anonymous identity
        </button>
        {status ? <p className="hint">{status}</p> : null}
      </section>
    </main>
  );
}

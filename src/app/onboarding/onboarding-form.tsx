"use client";

import { useActionState, useEffect, useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";
import { handleProblem, type AccountKind } from "@/lib/onboarding";
import { completeOnboarding, type OnboardingState } from "./actions";

type Category = { id: number; name: string };

export function OnboardingForm({
  categories,
  currentHandle,
}: {
  categories: Category[];
  currentHandle: string | null;
}) {
  const [state, formAction, pending] = useActionState<OnboardingState, FormData>(
    completeOnboarding,
    { error: null },
  );
  const [handle, setHandle] = useState(currentHandle ?? "");
  const [availability, setAvailability] = useState<"idle" | "checking" | "free" | "taken">(
    "idle",
  );
  // Derived at render: when the handle violates the shape rules we
  // never even query — and we avoid synchronous setState in the effect
  // (react-hooks/set-state-in-effect).
  const problem = handleProblem(handle);

  // 边输边查重: debounce 300ms, then ask the SECURITY DEFINER RPC as
  // the anonymous public would — never by reading the profiles table.
  useEffect(() => {
    if (problem) return;
    const timer = setTimeout(async () => {
      setAvailability("checking");
      const supabase = createSupabaseBrowserClient();
      const { data, error } = await supabase.rpc("handle_available", { p_handle: handle });
      if (error) {
        setAvailability("idle");
        return;
      }
      setAvailability(data === true ? "free" : "taken");
    }, 300);
    return () => clearTimeout(timer);
  }, [handle, problem]);

  return (
    <form action={formAction} className="flex w-full max-w-sm flex-col gap-4">
      <fieldset className="flex flex-col gap-2 text-sm">
        <legend className="mb-1">账号类型</legend>
        <label className="flex items-center gap-2">
          <input type="radio" name="accountKind" value="individual" defaultChecked required />
          个人
        </label>
        <label className="flex items-center gap-2">
          <input type="radio" name="accountKind" value="organisation" required />
          组织
        </label>
      </fieldset>

      <label className="flex flex-col gap-1 text-sm">
        类目
        <select
          name="categoryId"
          required
          defaultValue=""
          className="rounded-md border border-line bg-surface px-3 py-2"
        >
          <option value="" disabled>
            选择你的类目…
          </option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      </label>

      <label className="flex flex-col gap-1 text-sm">
        Handle（公开页地址用，3–30 位小写字母/数字/下划线）
        <input
          name="handle"
          required
          value={handle}
          onChange={(e) => setHandle(e.target.value.toLowerCase())}
          className="rounded-md border border-line bg-surface px-3 py-2 font-mono"
        />
      </label>
      <p
        aria-live="polite"
        className={`text-xs ${
          !problem && availability === "taken"
            ? "text-red-600"
            : !problem && availability === "free"
              ? "text-green-700"
              : "text-muted"
        }`}
      >
        {problem ??
          (availability === "checking"
            ? "查询中…"
            : availability === "free"
              ? "✓ 可用"
              : availability === "taken"
                ? "已被占用"
                : "")}
      </p>

      {state.error ? <p className="text-sm text-red-600">{state.error}</p> : null}

      <button
        type="submit"
        disabled={pending || availability === "taken"}
        className="rounded-md bg-brand-700 px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
      >
        {pending ? "保存中…" : "完成引导，进入 Dashboard"}
      </button>
    </form>
  );
}

export type { AccountKind };
